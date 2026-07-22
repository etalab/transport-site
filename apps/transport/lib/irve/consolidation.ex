defmodule Transport.IRVE.Consolidation do
  @moduledoc """
  This module:
  - takes the list of relevant IRVE datagouv_resources from data.gouv.fr,
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

  @report_output_base_name "consolidation_transport_irve_statique_rapport"
  @consolidated_file_no_dedup_base_name "consolidation_transport_avec_doublons_irve_statique"
  @consolidated_file_base_name "consolidation_transport_irve_statique"

  # The consolidated files can be large; uploading them can exceed ExAws' default 30s multipart
  # timeout. We lower the concurrency of the per-file parts (each part then gets more bandwidth
  # and uploads faster) and give each part a 1 minute ceiling.
  @s3_upload_timeout :timer.minutes(1)
  @s3_upload_max_concurrency 2

  def process(opts \\ []) do
    destination = Keyword.get(opts, :destination, :send_to_s3)
    debug = Keyword.get(opts, :debug, false)

    datagouv_resources = resource_list()
    datagouv_resource_ids = MapSet.new(datagouv_resources, & &1.resource_id)
    # Snapshot before processing mutates the DB, so `resource_status` reflects the pre-run state.
    db_ids_and_checksums = DB.IRVEValidFile.existing_datagouv_resource_ids_and_checksums()
    db_resource_ids = MapSet.new(db_ids_and_checksums, fn {resource_id, _checksum} -> resource_id end)

    processed_rows =
      datagouv_resources
      |> maybe_limit(opts[:limit])
      |> Task.async_stream(
        &process_or_rescue(&1, db_ids_and_checksums),
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
      |> Stream.map(&Transport.IRVE.ReportItem.from_result/1)
      |> Stream.map(&Transport.IRVE.ReportItem.put_resource_status(&1, db_resource_ids))
      |> maybe_log_items(debug)
      |> Enum.into([])

    report_rows = processed_rows ++ orphan_report_rows(db_resource_ids, datagouv_resource_ids)

    report = generate_report(report_rows, destination: destination)

    consolidated_df =
      Transport.IRVE.DatabaseExporter.build_data_frame()
      |> Transport.IRVE.Deduplicator.add_duplicates_column()

    write_consolidated_file(consolidated_df, @consolidated_file_no_dedup_base_name, destination)

    consolidated_df = Transport.IRVE.Deduplicator.discard_duplicates(consolidated_df)

    write_consolidated_file(consolidated_df, @consolidated_file_base_name, destination)

    Logger.info("IRVE consolidation process completed.")
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
    |> Transport.IRVE.Extractor.exclude_irrelevant_resources()
    |> Enum.sort_by(fn r -> [r.dataset_id, r.resource_id] end)
  end

  # Resources still in the DB but no longer listed on data.gouv.fr, appended as a block after the
  # processed rows (which are not processed this run, so they carry no consolidation outcome).
  def orphan_report_rows(db_resource_ids, datagouv_resource_ids) do
    db_resource_ids
    |> MapSet.difference(datagouv_resource_ids)
    |> MapSet.to_list()
    |> DB.IRVEValidFile.orphan_files()
    |> Enum.sort_by(&{&1.datagouv_dataset_id, &1.datagouv_resource_id})
    |> Enum.map(&Transport.IRVE.ReportItem.from_orphan_file/1)
  end

  # safety wrapper that we can use inside `Task.async_stream`
  def process_or_rescue(resource, db_ids_and_checksums) do
    process_resource(resource, db_ids_and_checksums)
  rescue
    error ->
      Logger.error(
        "IRVE consolidation: unexpected error for resource #{resource.resource_id} (#{resource.url})\n" <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      Sentry.capture_exception(error,
        stacktrace: __STACKTRACE__,
        extra: %{resource_id: resource.resource_id, url: resource.url}
      )

      {:error_occurred, error, resource}
  end

  def process_resource(resource, db_ids_and_checksums) do
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

      # This producer_is_org_check is not in the validator itself:
      # it’s not linked to the file content/format, but to how it is published on data.gouv.fr.
      # it is done after downloading the file in order to be able to report on the potential
      # loss of PDC count.
      with :producer_is_an_organization <- producer_is_org(resource),
           body = File.read!(path),
           checksum = Transport.IRVE.DatabaseImporter.compute_checksum(body),
           # Same content already stored: skip validation and insertion entirely.
           false <- MapSet.member?(db_ids_and_checksums, {resource.resource_id, checksum}),
           {%{valid: true}, validated_df} <- Transport.IRVE.Validator.validate_and_summarize(body, extension),
           import_status <- Transport.IRVE.DatabaseImporter.try_write_uncasted_df(validated_df, checksum, resource) do
        {import_status, resource}
      else
        :producer_not_an_organization -> {:producer_not_an_organization, resource}
        true -> {:already_up_to_date, resource}
        {%{file_level_errors: [_ | _] = errors}, nil} -> {:file_level_errors, resource, errors}
        {%{file_level_errors: []}, _validated_df} -> {:not_compliant_with_schema, resource}
      end
    end)
  end

  def generate_report(report_rows, destination: destination) do
    report_df =
      report_rows
      |> Enum.map(&Transport.IRVE.ReportItem.to_map/1)
      |> Explorer.DataFrame.new()
      # `select` orders columns in the provided order
      # (https://github.com/elixir-explorer/explorer/issues/1126)
      # sorted in a way that is more convenient when opening from
      # LibreOffice et al. (keeping error_message, sometimes long, at the end)
      |> Explorer.DataFrame.select([
        "dataset_id",
        "resource_id",
        "resource_status",
        "consolidation_status",
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
            "#{@report_output_base_name}.csv",
            timeout: @s3_upload_timeout,
            max_concurrency: @s3_upload_max_concurrency
          )
        end)

      :local_disk ->
        report_file = @report_output_base_name <> ".csv"
        Logger.info("Saving report locally to #{report_file}...")
        Explorer.DataFrame.to_csv!(report_df, report_file)
    end

    report_df
  end

  def write_consolidated_file(df, base_name, :send_to_s3) do
    Logger.info("Creating and uploading consolidated file (#{base_name}.csv) to S3...")

    with_tmp_file(fn consolidation_file ->
      Explorer.DataFrame.to_csv!(df, consolidation_file)

      upload_aggregate!(
        consolidation_file,
        "#{base_name}_#{timestamp()}.csv",
        "#{base_name}.csv",
        timeout: @s3_upload_timeout,
        max_concurrency: @s3_upload_max_concurrency
      )
    end)
  end

  def write_consolidated_file(df, base_name, :local_disk) do
    consolidation_file = base_name <> ".csv"
    Logger.info("Creating and saving consolidated file locally to #{consolidation_file}...")
    Explorer.DataFrame.to_csv!(df, consolidation_file)
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
    case download(resource.resource_id, resource.url, file_path) do
      # NOTE: we need to pass the original extension (provided in the URL) because some heuristics use it afterwards.
      # but the caching mechanism stores everything under the same `.dat` extension (so the file path is not enough
      # to keep the extension around)
      :ok -> work_fn.(file_path, extension)
      {:error, message} -> {:download_failed, resource, message}
    end
  after
    File.rm!(file_path)
  end

  # variant for dev work, where it is important to support permanent disk caching (fully offline, no etag)
  def with_maybe_cached_download_on_disk(resource, file_path, extension, true = _use_permanent_disk_cache, work_fn) do
    download_result =
      if File.exists?(file_path), do: :ok, else: download(resource.resource_id, resource.url, file_path)

    case download_result do
      :ok -> work_fn.(file_path, extension)
      {:error, message} -> {:download_failed, resource, message}
    end
  end

  # Returns `:ok` on success, or `{:error, message}` for a non-200 response.
  # Timeouts / transport errors still raise for now (caught upstream as `:error_occurred`).
  def download(resource_id, url, file) do
    Logger.info("Processing resource #{resource_id} (url=#{url})")
    %{status: status} = Transport.HTTPClient.get!(url, compressed: false, decode_body: false, into: File.stream!(file))

    if status == 200, do: :ok, else: {:error, "http_status=#{status}"}
  end

  defp producer_is_org(%{dataset_organisation_id: org_id}) do
    if org_id == "???", do: :producer_not_an_organization, else: :producer_is_an_organization
  end
end
