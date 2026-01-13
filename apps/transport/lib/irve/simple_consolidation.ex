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

  def process(opts \\ []) do
    destination = Keyword.get(opts, :destination, :send_to_s3)

    report_rows =
      resource_list()
      |> maybe_limit(opts[:limit])
      |> Task.async_stream(
        &process_or_rescue/1,
        ordered: true,
        on_timeout: :kill_task,
        timeout: :timer.seconds(60),
        max_concurrency: 10
      )
      # If a task times out, we get {:exit, :timeout} instead of {:ok, result} and the following line will crash.
      # This is intentional, we want to be aware of such timeouts.
      |> Stream.map(fn {:ok, result} -> result end)
      |> Stream.map(&Transport.IRVE.SimpleReportItem.from_result/1)
      |> maybe_log_items()
      |> Enum.into([])

    generate_report(report_rows, destination: destination)
  end

  # allow (quick at runtime, no config change/recompile) command-line `DEBUG=1` switch
  # essential to develop faster locally.
  def maybe_log_items(stream) do
    if System.get_env("DEBUG") == "1" do
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

    # Raise if the producer is not an organization. This check is not in the validator itself:
    # it’s not linked to the file content/format, but to how it is published on data.gouv.fr.
    Transport.IRVE.RawStaticConsolidation.ensure_producer_is_org!(resource)

    path = storage_path(resource.resource_id)
    extension = Path.extname(resource.url)

    Logger.info("Processing resource #{resource.resource_id} (#{resource.url})")

    with_maybe_cached_download_on_disk(resource, path, extension, use_permanent_disk_cache, fn path, extension ->
      estimated_pdc_count = File.stream!(path) |> Enum.count()
      resource = Map.put(resource, :estimated_pdc_count, estimated_pdc_count)

      # The code is convoluted mostly because we didn't go far enough on the validator work.
      # The validator will ultimately stop raising exceptions, and will instead return structures.
      # But currently if a cheap check fails, an exception is thrown, and we would lose the estimated PDC count,
      # something which is essential to report on for our current work.
      try do
        validation_result = Transport.IRVE.Validator.validate(path, extension)
        file_valid? = validation_result |> Transport.IRVE.Validator.full_file_valid?()

        if file_valid? do
          {Transport.IRVE.DatabaseImporter.try_write_to_db(path, resource.dataset_id, resource.resource_id), resource}
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

    base_name = "irve_static_consolidation_v2_report"

    case destination do
      :send_to_s3 ->
        Logger.info("Uploading report file (#{base_name}.csv) to S3...")

        with_tmp_file(fn report_file ->
          Explorer.DataFrame.to_csv!(report_df, report_file)

          upload_aggregate!(
            report_file,
            "#{base_name}_#{timestamp()}.csv",
            "#{base_name}.csv"
          )
        end)

      # TODO: tests should not go through this https://github.com/etalab/transport-site/issues/5109
      :local_disk ->
        report_file = base_name <> ".csv"
        Logger.info("Saving report to #{report_file}...")
        Explorer.DataFrame.to_csv!(report_df, report_file)
    end

    report_df
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
