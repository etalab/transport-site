defmodule Transport.Jobs.GTFSToGeoJSONConverterJob do
  @moduledoc """
  This will enqueue GTFS -> GeoJSON conversion jobs for all GTFS resources found in ResourceHistory
  """
  use Oban.Worker, max_attempts: 3
  alias Transport.Jobs.GTFSGenericConverter

  @impl true
  def perform(%{}) do
    GTFSGenericConverter.enqueue_all_conversion_jobs("GeoJSON", Transport.Jobs.SingleGTFSToGeoJSONConverterJob)
  end
end

defmodule Transport.Jobs.SingleGTFSToGeoJSONConverterJob do
  @moduledoc """
  Conversion Job of a GTFS to a GeoJSON, saving the resulting file in S3
  """
  use Oban.Worker, max_attempts: 3
  alias Transport.Jobs.GTFSGenericConverter

  @impl true
  def perform(%{args: %{"resource_history_id" => resource_history_id}}) do
    GTFSGenericConverter.perform_single_conversion_job(resource_history_id, "GeoJSON", Transport.GTFSToGeoJSONConverter)
  end
end

defmodule Transport.GTFSToGeoJSONConverter do
  @moduledoc """
  Given a GTFS file path, create from the file the corresponding geojson with the stops and line shapes if available.
  """
  @behaviour Transport.Converters.Converter

  @impl true
  def convert(gtfs_file_path, geojson_file_path) do
    binary_path = Path.join(Application.fetch_env!(:transport, :transport_tools_folder), "gtfs-geojson")

    case Transport.RamboLauncher.run(binary_path, ["--input", gtfs_file_path, "--output", geojson_file_path]) do
      {:ok, _} -> :ok
      {:error, e} -> {:error, e}
    end
  end

  @impl true
  def converter, do: "rust-transit/gtfs-to-geojson"

  @impl true
  def converter_version, do: "9ca9a25b895ba1b2fdf4d04e92895afec52d0608"
end
