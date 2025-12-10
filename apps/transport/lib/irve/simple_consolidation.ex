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
    tmp_file = download_resource_on_disk(resource)

    try do
      df = load_file_as_dataframe(tmp_file)

      validation_result = df |> Transport.IRVE.Validator.compute_validation()
      file_valid? = validation_result |> Transport.IRVE.Validator.full_file_valid?()

      Transport.IRVE.DatabaseImporter.write_to_db(
        tmp_file,
        resource.dataset_id,
        resource.resource_id
      )

      {:ok, file_valid?}
    after
      File.rm!(tmp_file)
    end
  end

  def download_resource_on_disk(resource) do
    # TODO: improve local storage contract (we want a clear place for production)
    tmp_file = Path.join(System.tmp_dir(), "irve-resource-#{resource.resource_id}.dat")

    # NOTE: this will be improved:
    # - dev cache must allow permanent local storage, to allow iterating while offline
    # - production cache must be smarter (use etag if they are provided, & reliable, on the source servers)
    if File.exists?(tmp_file) do
      Logger.info("File for resource #{resource.resource_id} already exists ; skipping download (#{tmp_file})")
    else
      Logger.info(
        "Processing resource #{resource.resource_id} (url=#{resource.url}, dataset_id=#{resource.dataset_id})"
      )

      # TODO: find how to forbid storage on the disk if status is not 200 (via a Req step)
      %{status: status} =
        Transport.HTTPClient.get!(resource.url, compressed: false, decode_body: false, into: File.stream!(tmp_file))

      unless status == 200 do
        # No need to remove the file as Req says about the into: option:
        # https://hexdocs.pm/req/Req.html#new/1
        # "Note that the collectable is only used, if the response status is 200.
        # In other cases, the body is accumulated and processed as usual."
        raise "Error processing resource (#{resource.resource_id}) (http_status=#{status})"
      end
    end

    tmp_file
  end

  def load_file_as_dataframe(path) do
    # NOTE: `infer_schema_length: nil` enforces strings everywhere
    Explorer.DataFrame.from_csv!(path, infer_schema_length: 0)
  end
end
