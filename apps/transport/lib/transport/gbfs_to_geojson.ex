defmodule Transport.GbfsToGeojson do
  @moduledoc """
  Converts a GBFS feed to useful GeoJSONs
  """
  alias Transport.GBFSMetadata

  def fetch_gbfs_endpoint!(url) do
    %{status_code: 200, body: body} = http_client().get!(url)
    Jason.decode!(body)
  end

  def station_information_geojson(url) do
    json = fetch_gbfs_endpoint!(url)
    convert_station_information!(json)
  end

  def feed_url_from_payload(payload, feed_name) do
    payload |> GBFSMetadata.first_feed() |> GBFSMetadata.feed_url_by_name(feed_name)
  end

  def gbfs_geojsons(url) do
    payload = fetch_gbfs_endpoint!(url)

    %{}
    |> add_station_information(payload)
    |> add_station_status(payload)
  end

  def add_station_information(resp_data, payload) do
    payload
    |> feed_url_from_payload("station_information")
    |> case do
      nil -> resp_data
      url -> geojson = url |> station_information_geojson()
            resp_data |> Map.put("stations", geojson)
    end
  rescue
      _e -> resp_data
  end

  def add_station_status(%{"stations" => stations_geojson} = resp_data, payload) do
    payload
      |> feed_url_from_payload("station_status")
      |> case do
        nil -> resp_data
        url -> geojson = url |> station_status_to_geojson!(stations_geojson)
            resp_data |> Map.put("stations", geojson)
    end
  rescue
      _e -> resp_data
  end

  def add_station_status(resp_data, _payload) do
    resp_data
  end

  def station_status_to_geojson!(station_status_url, stations_geojson) do
    json = fetch_gbfs_endpoint!(station_status_url)
    station_status = json
    |> Map.fetch!("data")
    |> Map.fetch!("stations")

    stations_geojson
    |> Enum.map(fn s ->
      station_id = s["properties"]["station_id"]
      status = station_status |> Enum.find(fn s -> s["station_id"] == station_id end)
      put_in(s["properties"]["station_status"], status)
    end)
  end

  def convert_station_information!(json) do
    json
    |> Map.fetch!("data")
    |> Map.fetch!("stations")
    |> Enum.map(fn s ->
      %{
        "type" => "Feature",
        "geometry" => %{
          "type" => "Point",
          "coordinates" => [s["lon"], s["lat"]]
        },
        "properties" => %{
          "name" => s["name"],
          "station_id" => s["station_id"]
        }
      }
    end)
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
