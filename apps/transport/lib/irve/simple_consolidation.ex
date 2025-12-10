defmodule Transport.IRVE.SimpleConsolidation do
  require Logger

  @moduledoc """
  A module that consolidates simple IRVE data for faster access.
  """

  def process do
    df =
      resource_list()
      |> Task.async_stream(
        &process_or_rescue/1,
        ordered: true,
        on_timeout: :kill_task,
        timeout: :timer.seconds(60),
        max_concurrency: 10
      )
      |> Stream.map(fn {:ok, result} -> result end)
      |> Stream.map(&prepare_report_item/1)
      |> Enum.into([])
      |> Explorer.DataFrame.new()

    report_file = "irve-processed-resources.csv"
    Logger.info("Saving report to #{report_file}...")
    Explorer.DataFrame.to_csv!(df, report_file)

    # NOTE: to be removed ; but nicely displays what happened
    df["status"]
    |> Explorer.Series.frequencies()
    |> IO.inspect(IEx.inspect_opts())
  end

  def base_report_item(resource) do
    resource
    |> Map.take([:dataset_id, :resource_id, :url, :dataset_title])
    |> Map.put_new(:error_message, nil)
    |> Map.put_new(:error_type, nil)
  end

  def prepare_report_item({:error_occurred, error, resource}) do
    base_report_item(resource)
    |> Map.put(:status, :error_occurred)
    |> Map.merge(%{
      error_message: Exception.message(error),
      error_type: error.__struct__ |> inspect()
    })
    |> Map.update!(:status, &to_string/1)
  end

  def prepare_report_item({status, resource}) do
    base_report_item(resource)
    |> Map.merge(%{status: status})
    |> Map.update!(:status, &to_string/1)
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
      {:error_occurred, error, resource}
  end

  def process_resource(resource) do
    # optionnally, for dev especially, we can keep files around until we manually delete them
    use_permanent_disk_cache = Application.get_env(:transport, :irve_consolidation_caching, false)
    path = storage_path(resource.resource_id)

    with_maybe_cached_download_on_disk(resource, path, use_permanent_disk_cache, fn path ->
      df = load_file_as_dataframe(path)

      validation_result = df |> Transport.IRVE.Validator.compute_validation()
      file_valid? = validation_result |> Transport.IRVE.Validator.full_file_valid?()

      if file_valid? do
        try_import_into_db(resource, path)
      else
        {:not_compliant_with_schema, resource}
      end
    end)
  end

  def try_import_into_db(resource, path) do
    try do
      Transport.IRVE.DatabaseImporter.write_to_db(
        path,
        resource.dataset_id,
        resource.resource_id
      )

      {:import_successful, resource}
    rescue
      x in [Ecto.ConstraintError] ->
        # TODO: encapsulate that logic inside `write_to_db`, returning just an atom there
        if x.type == :unique && x.constraint == "irve_valid_file_resource_datagouv_id_checksum_index" do
          {:already_in_db, resource}
        else
          reraise(x, __STACKTRACE__)
        end
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

  def load_file_as_dataframe(path) do
    # NOTE: `infer_schema_length: 0` enforces strings everywhere
    case Explorer.DataFrame.from_csv(path, infer_schema_length: 0) do
      {:ok, df} -> df
      {:error, error} -> raise error
    end
  end
end
