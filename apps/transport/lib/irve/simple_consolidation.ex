defmodule Transport.IRVE.SimpleConsolidation do
  @moduledoc """
  This module:
  - takes the list of relevant IRVE resources from data.gouv.fr,
  - downloads each resource file,
  - validates it,
  - and if valid writes the PDCs and file to the database.
  If there is a previous version of the same resource already in the database,
  its PDCs are replaced by the newly imported ones.

  The module then reports on the outcome of each resource processing in a CSV file
  (defaulting to upload it to S3, but can also be saved on local disk for dev/testing).
  """

  require Logger
  import Transport.S3.AggregatesUploader

  @report_output_base_name "consolidation_transport_avec_doublons_irve_statique_rapport"
  @consolidated_file_no_dedup_base_name "consolidation_transport_avec_doublons_irve_statique"

  def process(opts \\ []) do
    destination = Keyword.get(opts, :destination, :send_to_s3)
    debug = Keyword.get(opts, :debug, false)

    report_rows =
      resource_list()
      |> maybe_limit(opts[:limit])
      |> Task.async_stream(
        &process_or_rescue/1,
        ordered: true,
        on_timeout: :kill_task,
        # Underlying DB operation has 90 seconds timeout, see DatabaseImporter
        # Let’s get some room here for downloading, validating, etc.
        timeout: :timer.seconds(120),
        max_concurrency: 5
      )
      # If a task times out, we get {:exit, :timeout} instead of {:ok, result} and the following line will crash.
      # This is intentional, we want to be aware of such timeouts.
      |> Stream.map(fn {:ok, result} -> result end)
      |> Stream.map(&Transport.IRVE.SimpleReportItem.from_result/1)
      |> maybe_log_items(debug)
      |> Enum.into([])

    report = generate_report(report_rows, destination: destination)
    write_consolidated_file(destination)
    Logger.info("IRVE simple consolidation process completed.")
    {:ok, report}
  end

  # allow (quick at runtime, no config change/recompile) command-line `DEBUG=1` switch
  # essential to develop faster locally.
  def maybe_log_items(stream, debug) do
    if debug do
      stream
      # credo:disable-for-next-line Credo.Check.Warning.IoInspect
      |> Stream.each(&IO.inspect(&1, IEx.inspect_opts()))
    else
      stream
    end
  end

  def maybe_limit(stream, limit) when is_integer(limit), do: stream |> Stream.take(limit)
  def maybe_limit(stream, nil), do: stream

  def resource_list do
    Transport.IRVE.Extractor.datagouv_resources()
    |> Transport.IRVE.RawStaticConsolidation.exclude_irrelevant_resources()
    |> Enum.sort_by(fn r -> [r.dataset_id, r.resource_id] end)
  end

  # safety wrapper that we can use inside `Task.async_stream`
  def process_or_rescue(resource) do
    process_resource(resource)
  rescue
    error ->
      {:error_occurred, error, resource}
  end

  def process_resource(resource) do
    # optionally, for dev especially, we can keep files around until we manually delete them
    use_permanent_disk_cache = Application.get_env(:transport, :irve_consolidation_caching, false)

    path = storage_path(resource.resource_id)
    extension = Path.extname(resource.url)

    Logger.info("Processing resource #{resource.resource_id} (#{resource.url})")

    with_maybe_cached_download_on_disk(resource, path, extension, use_permanent_disk_cache, fn path, extension ->
      # minus header line
      estimated_pdc_count = (File.stream!(path) |> Enum.count()) - 1

      resource =
        resource
        |> Map.put(:estimated_pdc_count, estimated_pdc_count)
        |> Map.put(:file_extension, extension)

      # The code is convoluted mostly because we didn't go far enough on the validator work.
      # The validator will ultimately stop raising exceptions, and will instead return structures.
      # But currently if a cheap check fails, an exception is thrown, and we would lose the estimated PDC count,
      # something which is essential to report on for our current work.
      try do
        # Raise if the producer is not an organization. This check is not in the validator itself:
        # it’s not linked to the file content/format, but to how it is published on data.gouv.fr.
        # it is done after downloading the file in order to be able to report on the potential
        # loss of PDC count.
        Transport.IRVE.RawStaticConsolidation.ensure_producer_is_org!(resource)

        validation_result = Transport.IRVE.Validator.validate(path, extension)
        file_valid? = validation_result |> Transport.IRVE.Validator.full_file_valid?()

        if file_valid? do
          {Transport.IRVE.DatabaseImporter.try_write_to_db(path, resource), resource}
        else
          {:not_compliant_with_schema, resource}
        end
      rescue
        error ->
          {:error_occurred, error, resource}
      end
    end)
  end

  def generate_report(report_rows, destination: destination) do
    report_df =
      report_rows
      |> Enum.map(&Transport.IRVE.SimpleReportItem.to_map/1)
      |> Explorer.DataFrame.new()
      # `select` orders columns in the provided order
      # (https://github.com/elixir-explorer/explorer/issues/1126)
      # sorted in a way that is more convenient when opening from
      # LibreOffice et al. (keeping error_message, sometimes long, at the end)
      |> Explorer.DataFrame.select([
        "dataset_id",
        "resource_id",
        "status",
        "error_type",
        "estimated_pdc_count",
        "file_extension",
        "url",
        "dataset_title",
        "datagouv_organization_or_owner",
        "datagouv_last_modified",
        "error_message"
      ])

    case destination do
      :send_to_s3 ->
        Logger.info("Uploading report file (#{@report_output_base_name}.csv) to S3...")

        with_tmp_file(fn report_file ->
          Explorer.DataFrame.to_csv!(report_df, report_file)

          upload_aggregate!(
            report_file,
            "#{@report_output_base_name}_#{timestamp()}.csv",
            "#{@report_output_base_name}.csv"
          )
        end)

      :local_disk ->
        report_file = @report_output_base_name <> ".csv"
        Logger.info("Saving report locally to #{report_file}...")
        Explorer.DataFrame.to_csv!(report_df, report_file)
    end

    report_df
  end

  def write_consolidated_file(:send_to_s3) do
    Logger.info("Creating and uploading consolidated file (#{@consolidated_file_no_dedup_base_name}.csv) to S3...")

    with_tmp_file(fn consolidation_file ->
      Transport.IRVE.DatabaseExporter.export_to_csv(consolidation_file)

      upload_aggregate!(
        consolidation_file,
        "#{@consolidated_file_no_dedup_base_name}_#{timestamp()}.csv",
        "#{@consolidated_file_no_dedup_base_name}.csv"
      )
    end)
  end

  def write_consolidated_file(:local_disk) do
    consolidation_file = @consolidated_file_no_dedup_base_name <> ".csv"
    Logger.info("Creating and saving consolidated file locally to #{consolidation_file}...")
    Transport.IRVE.DatabaseExporter.export_to_csv(consolidation_file)
  end

  def storage_path(resource_id) do
    # NOTE: to be finetuned for production, in particular
    Path.join(System.tmp_dir(), "irve-resource-#{resource_id}.dat")
  end

  # TODO: 🚨 replace the 2 pattern-matching variants below by a more intelligible "Req steps" use.
  # This works for now though, to allow me local-only work.

  # regular workflow: process the file then delete it afterwards, no matter what, to ensure
  # the files do not stack up on the production disk.
  def with_maybe_cached_download_on_disk(resource, file_path, extension, false = _use_permanent_disk_cache, work_fn) do
    download!(resource.resource_id, resource.url, file_path)
    # NOTE: we need to pass the original extension (provided in the URL) because some heuristics use it afterwards.
    # but the caching mechanism stores everything under the same `.dat` extension (so the file path is not enough
    # to keep the extension around)
    work_fn.(file_path, extension)
  after
    File.rm!(file_path)
  end

  # variant for dev work, where it is important to support permanent disk caching (fully offline, no etag)
  def with_maybe_cached_download_on_disk(resource, file_path, extension, true = _use_permanent_disk_cache, work_fn) do
    if !File.exists?(file_path), do: download!(resource.resource_id, resource.url, file_path)
    work_fn.(file_path, extension)
  end

  def download!(resource_id, url, file) do
    Logger.info("Processing resource #{resource_id} (url=#{url})")
    %{status: status} = Transport.HTTPClient.get!(url, compressed: false, decode_body: false, into: File.stream!(file))

    unless status == 200 do
      raise "Error processing resource (#{resource_id}) (http_status=#{status})"
    end
  end
end
