defmodule Transport.Jobs.GtfsToGeojsonConverterJob do
  @moduledoc """
  This will enqueue GTFS -> GeoJSON conversion jobs for all GTFS resources found in ResourceHistory
  """
  use Oban.Worker, max_attempts: 3
  alias DB.{Repo, ResourceHistory}
  alias Transport.Jobs.GtfsGenericConverter

  @impl true
  def perform(%{}) do
    Transport.S3.create_bucket_if_needed!(:history)
    GtfsGenericConverter.enqueue_all_conversion_jobs("GeoJSON", Transport.Jobs.SingleGtfsToGeojsonConverterJob)
  end
end

defmodule Transport.Jobs.SingleGtfsToGeojsonConverterJob do
  @moduledoc """
  Conversion Job of a GTFS to a GeoJSON, saving the resulting file in S3
  """
  use Oban.Worker, max_attempts: 3
  require Logger
  alias Transport.Jobs.GtfsGenericConverter

  @impl true
  def perform(%{args: %{"resource_history_id" => resource_history_id}}) do
    GtfsGenericConverter.perform_single_conversion_job(resource_history_id, "GeoJSON", Transport.GtfsToGeojsonConverter)
  end
end

defmodule Transport.GtfsToGeojsonConverter do
  @moduledoc """
  Given a GTFS file path, create from the file the corresponding geojson with the stops and line shapes if available.
  """
  @spec convert(binary(), binary()) :: :ok | {:error, any()}
  def convert(gtfs_file_path, geojson_file_path) do
    binary_path = Path.join(Application.fetch_env!(:transport, :transport_tools_folder), "gtfs-geojson")

    case Transport.RamboLauncher.run(binary_path, ["--input", gtfs_file_path, "--output", geojson_file_path]) do
      {:ok, _} -> :ok
      {:error, e} -> {:error, e}
    end
  end
end
