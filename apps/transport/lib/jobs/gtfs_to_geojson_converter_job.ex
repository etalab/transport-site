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
  alias DB.{Repo, ResourceHistory}
  alias Transport.Jobs.GtfsGenericConverter

  @impl true
  def perform(%{args: %{"resource_history_id" => resource_history_id}}) do
    resource_history = ResourceHistory |> Repo.get(resource_history_id)

    if GtfsGenericConverter.is_resource_gtfs?(resource_history) and not geojson_exists?(resource_history) do
      generate_and_upload_geojson(resource_history)
    end

    :ok
  end

  @spec geojson_exists?(any) :: boolean
  def geojson_exists?(resource_history), do: GtfsGenericConverter.format_exists?("GeoJSON", resource_history)

  def generate_and_upload_geojson(resource_history) do
    GtfsGenericConverter.generate_and_upload_conversion(resource_history, "GeoJSON", Transport.GtfsToGeojsonConverter)
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
