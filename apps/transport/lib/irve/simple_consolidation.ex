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
      |> Enum.into([])

    generate_report(report_rows, destination: destination)
  end

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

    with_maybe_cached_download_on_disk(resource, path, use_permanent_disk_cache, fn path ->
      validation_result = path |> Transport.IRVE.Validator.validate()
      file_valid? = validation_result |> Transport.IRVE.Validator.full_file_valid?()

      if file_valid? do
        {Transport.IRVE.DatabaseImporter.try_write_to_db(path, resource.dataset_id, resource.resource_id), resource}
      else
        {:not_compliant_with_schema, resource}
      end
    end)
  end

  def generate_report(report_rows, destination: destination) do
    report_df =
      report_rows
      |> Enum.map(&Transport.IRVE.SimpleReportItem.to_map/1)
      |> Explorer.DataFrame.new()

    case destination do
      :send_to_s3 ->
        with_tmp_file(fn report_file ->
          Explorer.DataFrame.to_csv!(report_df, report_file)

          upload_aggregate!(
            report_file,
            "irve_processed_resources#{timestamp()}.csv",
            "irve_processed_resources.csv"
          )
        end)

      :local_disk ->
        report_file = "irve_processed_resources.csv"
        Logger.info("Saving report to #{report_file}...")
        Explorer.DataFrame.to_csv!(report_df, report_file)
    end
  end

  def storage_path(resource_id) do
    # NOTE: to be finetuned for production, in particular
    Path.join(System.tmp_dir(), "irve-resource-#{resource_id}.dat")
  end

  # TODO: 🚨 replace the 2 pattern-matching variants below by a more intelligible "Req steps" use.
  # This works for now though, to allow me local-only work.

  # regular workflow: process the file then delete it afterwards, no matter what, to ensure
  # the files do not stack up on the production disk.
  def with_maybe_cached_download_on_disk(resource, file_path, false = _use_permanent_disk_cache, work_fn) do
    download!(resource.resource_id, resource.url, file_path)
    work_fn.(file_path)
  after
    File.rm!(file_path)
  end

  # variant for dev work, where it is important to support permanent disk caching (fully offline, no etag)
  def with_maybe_cached_download_on_disk(resource, file_path, true = _use_permanent_disk_cache, work_fn) do
    if !File.exists?(file_path), do: download!(resource.resource_id, resource.url, file_path)
    work_fn.(file_path)
  end

  def download!(resource_id, url, file) do
    Logger.info("Processing resource #{resource_id} (url=#{url})")
    %{status: status} = Transport.HTTPClient.get!(url, compressed: false, decode_body: false, into: File.stream!(file))

    unless status == 200 do
      raise "Error processing resource (#{resource_id}) (http_status=#{status})"
    end
  end
end
