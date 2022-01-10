defmodule Transport.Jobs.GtfsToGeojsonConverterJob do
  @moduledoc """
  This will enqueue GTFS -> GeoJSON conversion jobs for all GTFS resources found in ResourceHistory
  """
  use Oban.Worker, max_attempts: 3
  alias DB.{Repo, ResourceHistory}
  alias Transport.Jobs.GtfsConverter

  @impl true
  def perform(%{}) do
    Transport.S3.create_bucket_if_needed!(:history)
    GtfsConverter.enqueue_all_conversion_jobs("GeoJSON", Transport.Jobs.SingleGtfsToGeojsonConverterJob)
  end
end

defmodule Transport.Jobs.SingleGtfsToGeojsonConverterJob do
  @moduledoc """
  Conversion Job of a GTFS to a GeoJSON, saving the resulting file in S3
  """
  use Oban.Worker, max_attempts: 3
  require Logger
  alias DB.{DataConversion, Repo, ResourceHistory}
  alias Transport.Jobs.GtfsConverter

  @impl true
  def perform(%{args: %{"resource_history_id" => resource_history_id}}) do
    resource_history = ResourceHistory |> Repo.get(resource_history_id)

    if GtfsConverter.is_resource_gtfs?(resource_history) and not geojson_exists?(resource_history) do
      generate_and_upload_geojson(resource_history)
    end

    :ok
  end

  @spec geojson_exists?(any) :: boolean
  def geojson_exists?(resource_history), do: GtfsConverter.format_exists?("GeoJSON", resource_history)

  def generate_and_upload_geojson(%{
        id: resource_history_id,
        datagouv_id: resource_datagouv_id,
        payload: %{"uuid" => resource_uuid, "permanent_url" => resource_url, "filename" => resource_filename}
      }) do
    Logger.info("Starting conversion of download uuid #{resource_uuid}, from GTFS to GeoJSON")

    gtfs_file_path =
      System.tmp_dir!() |> Path.join("conversion_gtfs_geojson_#{resource_history_id}_#{:os.system_time(:millisecond)}")

    geojson_file_path = "#{gtfs_file_path}.geojson"

    try do
      %{status_code: 200, body: body} = Transport.Shared.Wrapper.HTTPoison.impl().get!(resource_url)

      File.write!(gtfs_file_path, body)

      :ok = Transport.GtfsToGeojsonConverter.convert(gtfs_file_path, geojson_file_path)
      file = geojson_file_path |> File.read!()

      geojson_file_name = resource_filename |> geojson_file_name()
      Transport.S3.upload_to_s3!(:history, file, geojson_file_name)

      {:ok, %{size: filesize}} = File.stat(geojson_file_path)

      %DataConversion{
        convert_from: "GTFS",
        convert_to: "GeoJSON",
        resource_history_uuid: resource_uuid,
        payload: %{
          filename: geojson_file_name,
          permanent_url: Transport.S3.permanent_url(:history, geojson_file_name),
          resource_datagouv_id: resource_datagouv_id,
          filesize: filesize
        }
      }
      |> Repo.insert!()
    after
      File.rm(gtfs_file_path)
      File.rm(geojson_file_path)
    end
  end

  def geojson_file_name(resource_name), do: "conversions/gtfs-to-geojson/#{resource_name}.geojson"
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
