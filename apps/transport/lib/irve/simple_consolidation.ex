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
        process_resource(resource)
      end,
      on_timeout: :kill_task,
      max_concurrency: 10
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

  def process_resource(resource) do
    tmp_file = download_resource_on_disk(resource)
    # |> IO.inspect(IEx.inspect_opts())
    df = load_file_as_dataframe(tmp_file)

    # send to validation
    # |> IO.inspect(IEx.inspect_opts())
    validation_result = df |> Transport.IRVE.Validator.compute_validation()
    file_valid? = validation_result |> Transport.IRVE.Validator.full_file_valid?()

    # write in database
    {:ok, file_valid?}
  rescue
    error ->
      # Logger.error("Error processing resource #{resource.resource_id} : #{inspect(error)}")
      {:error, error}
  end

  def download_resource_on_disk(resource) do
    # TODO: improve local storage contract (we want a clear place for production)
    tmp_file = Path.join(System.tmp_dir(), "irve-resource-#{resource.resource_id}.dat")

    if File.exists?(tmp_file) do
      Logger.info("File for resource #{resource.resource_id} already exists ; skipping download (#{tmp_file})")
    else
      # download resource
      Logger.info(
        "Processing resource #{resource.resource_id} (url=#{resource.url}, dataset_id=#{resource.dataset_id})"
      )

      # TODO: the next line uses local dev cache but doesn’t store on disk.
      %{body: body, status: status} = Transport.IRVE.RawStaticConsolidation.download_resource_content!(resource.url)

      unless status == 200 do
        raise "Error processing resource (#{resource.resource_id}) (http_status=#{status})"
      end

      File.write!(tmp_file, body)
    end

    tmp_file
  end

  def load_file_as_dataframe(path) do
    # NOTE: `infer_schema_length: nil` enforces strings everywhere
    Explorer.DataFrame.from_csv!(path, infer_schema_length: 0)
  end
end
