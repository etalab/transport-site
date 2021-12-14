defmodule Transport.GtfsToGeojsonConverterJob do
  @moduledoc """

  """
  use Oban.Worker, max_attempts: 1
  import Logger
  alias DB.{GtfsToGeojsonConversion, Repo, Resource, ResourceHistory}

  @impl true
  def perform(%Oban.Job{args: %{"resource_history_id" => resource_history_id}}) do
    resource_history = ResourceHistory |> Repo.get(resource_history_id)

    case is_resource_gtfs?(resource_history) do
      {:ok, true} ->
        case resource_history |> geojson_exists?() do
          true -> :ok
          false -> generate_and_upload_geojson(resource_history)
                  :ok
        end

      _ ->
        :ok
    end
  end

  def is_resource_gtfs?(nil), do: {:error, "resource history not found"}
  def is_resource_gtfs?(%{payload: %{"format" => "GTFS"}}), do: {:ok, true}
  def is_resource_gtfs?(_), do: {:ok, false}

  @spec geojson_exists?(any) :: boolean
  def geojson_exists?(%{payload: %{"uuid" => resource_uuid}}) do
    GtfsToGeojsonConversion
    |> Repo.get_by(resource_history_uuid: resource_uuid) !== nil
  end

  def geojson_exists?(_), do: false

  def generate_and_upload_geojson(%{
        id: resource_history_id,
        payload: %{"uuid" => resource_uuid, "permanent_url" => resource_url, "filename" => resource_filename}
      }) do
    gtfs_file_path = System.tmp_dir!() |> Path.join("#{resource_history_id}_#{:os.system_time(:millisecond)}")
    %{status_code: 200, body: body} = Transport.Shared.Wrapper.HTTPoison.impl().get!(resource_url, [], follow_redirect: true)
    File.write!(gtfs_file_path, body)

    geojson_file_path = "#{gtfs_file_path}.geojson"
    :ok = Transport.GtfsToGeojsonConverter.convert(gtfs_file_path, geojson_file_path)
    file = geojson_file_path |> File.read!()

    Transport.S3.upload_to_s3!(file, resource_filename |> geojson_file_name())

    File.rm(gtfs_file_path)
    File.rm(geojson_file_path)

    %DB.GtfsToGeojsonConversion{datagouv_id: "xxx", resource_history_uuid: resource_uuid, payload: %{"coucou" => "toi"}}
    |> Repo.insert!()
  end

  def geojson_file_name(resource_name), do: "conversions/gtfs-to-geojson/#{resource_name}.geojson"
end
