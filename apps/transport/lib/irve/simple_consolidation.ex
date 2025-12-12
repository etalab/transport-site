defmodule Transport.IRVE.SimpleConsolidation do
  require Logger
  import Transport.S3.AggregatesUploader

  @moduledoc """
  A module that consolidates simple IRVE data for faster access.
  """

  defmodule ReportRow do
    @moduledoc """
    Quick & dirty structure to massage the outcome into a report with all the same keys
    (as expected by the `DataFrame` that we use to create the CSV file).

    It's all quiet tied to the other module here.
    """
    @enforce_keys [:dataset_id, :resource_id, :url, :dataset_title, :status]
    defstruct [:dataset_id, :resource_id, :url, :dataset_title, :status, :error_message, :error_type]

    def from_result({:error_occurred, error, resource}) do
      new(resource, :error_occurred, error)
    end

    def from_result({status, resource}) do
      new(resource, status, nil)
    end

    def to_map(%__MODULE__{} = report_row) do
      report_row
      |> Map.from_struct()
      |> Map.update!(:status, &to_string/1)
    end

    defp new(resource, status, error) do
      %__MODULE__{
        dataset_id: resource.dataset_id,
        resource_id: resource.resource_id,
        url: resource.url,
        dataset_title: resource.dataset_title,
        status: status,
        error_message: maybe_error_message(error),
        error_type: maybe_error_type(error)
      }
    end

    defp maybe_error_message(nil), do: nil
    defp maybe_error_message(error), do: Exception.message(error)

    defp maybe_error_type(nil), do: nil
    defp maybe_error_type(error), do: error.__struct__ |> inspect()
  end

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
      |> Stream.map(fn {:ok, result} -> result end)
      |> Stream.map(&ReportRow.from_result/1)
      |> Enum.into([])

    generate_report(report_rows, destination: destination)
  end

  def resource_list do
    Transport.IRVE.Extractor.datagouv_resources()
    |> Transport.IRVE.RawStaticConsolidation.exclude_irrelevant_resources()
    # |> maybe_filter(options[:filter])
    |> Enum.sort_by(fn r -> [r.dataset_id, r.resource_id] end)
  end

  # safety wrapper that we can use inside `Task.async_stream`
  def process_or_rescue(resource) do
    process_resource(resource)
  rescue
    error ->
      dbg(error)
      {:error_occurred, error, resource}
  end

  def process_resource(resource) do
    # optionally, for dev especially, we can keep files around until we manually delete them
    use_permanent_disk_cache = Application.get_env(:transport, :irve_consolidation_caching, false)
    path = storage_path(resource.resource_id)

    with_maybe_cached_download_on_disk(resource, path, use_permanent_disk_cache, fn path ->
      dbg(path)
      validation_result = path |> Transport.IRVE.Validator.validate()
      dbg(validation_result)
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
      |> Enum.map(&ReportRow.to_map/1)
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

    # NOTE: to be removed ; but nicely displays what happened
    # report_df["status"]
    # |> Explorer.Series.frequencies()
    # |> IO.inspect(IEx.inspect_opts())
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
    IO.puts("Deleting temporary file #{file_path}...")
    File.rm!(file_path)
  end

  # variant for dev work, where it is important to support permanent disk caching (fully offline, no etag)
  def with_maybe_cached_download_on_disk(resource, file_path, true = _use_permanent_disk_cache, work_fn) do
    if !File.exists?(file_path), do: download!(resource.resource_id, resource.url, file_path)
    work_fn.(file_path)
  end

  def download!(resource_id, url, file) do
    Logger.info("Processing resource #{resource_id} (url=#{url})")
    IO.puts("Downloading resource #{resource_id} from #{url}...")
    %{status: status} = Transport.HTTPClient.get!(url, compressed: false, decode_body: false, into: File.stream!(file))
    IO.puts("there should be now a status…")
    dbg(status)

    unless status == 200 do
      raise "Error processing resource (#{resource_id}) (http_status=#{status})"
    end
  end
end
