defmodule Transport.IRVE.SimpleConsolidation do
  require Logger

  @moduledoc """
  A module that consolidates simple IRVE data for faster access.
  """

  def process do
    # Get list of datagouv resources
    resource_list()
    # Then for each resource, launch a kind of job that will dl the resource, etc.
    # |> Enum.drop(2)
    # |> Enum.take(10)
    |> Task.async_stream(
      fn resource ->
        process_or_rescue(resource)
      end,
      on_timeout: :kill_task,
      timeout: :timer.seconds(60),
      max_concurrency: 5
    )
    |> Stream.map(fn {:ok, result} -> result end)
    |> Enum.into([])

    # |> Enum.frequencies()
    # |> IO.inspect()
  end

  def resource_list do
    Transport.IRVE.Extractor.datagouv_resources()
    |> Transport.IRVE.RawStaticConsolidation.exclude_irrelevant_resources()
    # |> maybe_filter(options[:filter])
    |> Enum.sort_by(fn r -> [r.dataset_id, r.resource_id] end)
  end

  def process_or_rescue(resource) do
    process_resource(resource)
  rescue
    error ->
      # Logger.error("Error processing resource #{resource.resource_id} : #{inspect(error)}")
      {:error, error}
  end

  def process_resource(resource) do
    # optionnally, for dev especially, we can keep files around until we manually delete them
    use_permanent_disk_cache = Application.get_env(:transport, :irve_consolidation_caching, false)
    path = storage_path(resource.resource_id)

    with_maybe_cached_download_on_disk(resource, path, use_permanent_disk_cache, fn path ->
      df = load_file_as_dataframe(path)

      validation_result = df |> Transport.IRVE.Validator.compute_validation()
      file_valid? = validation_result |> Transport.IRVE.Validator.full_file_valid?()

      Transport.IRVE.DatabaseImporter.write_to_db(
        path,
        resource.dataset_id,
        resource.resource_id
      )

      {:ok, file_valid?}
    end)
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

  def load_file_as_dataframe(path) do
    # NOTE: `infer_schema_length: 0` enforces strings everywhere
    case Explorer.DataFrame.from_csv(path, infer_schema_length: 0) do
      {:ok, df} -> df
      {:error, error} -> raise error
    end
  end
end
