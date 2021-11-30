defmodule Transport.GbfsToGeojson do
  @moduledoc """
  Converts a GBFS feed to useful GeoJSONs
  """
  alias Transport.GBFSMetadata

  @doc """
  Main module function: returns a map of geojsons generated from the GBFS endpoint
  """
  def gbfs_geojsons(url) do
    payload = fetch_gbfs_endpoint!(url)

    %{}
    |> add_station_information(payload)
    |> add_station_status(payload)
    |> add_free_bike_status(payload)
    |> add_geofencing_zones(payload)
  end

  def add_station_information(resp_data, payload) do
    payload
    |> feed_url_from_payload("station_information")
    |> case do
      nil ->
        resp_data

      url ->
        geojson = station_information_geojson(url)
        resp_data |> Map.put("stations", geojson)
    end
  rescue
    _e -> resp_data
  end

  defp station_information_geojson(url) do
    features =
      url
      |> fetch_gbfs_endpoint!()
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

    %{
      "type" => "FeatureCollection",
      "features" => features
    }
  end

  def add_station_status(%{"stations" => stations_geojson} = resp_data, payload) do
    payload
    |> feed_url_from_payload("station_status")
    |> case do
      nil ->
        resp_data

      url ->
        geojson = url |> station_status_to_geojson!(stations_geojson)
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

    station_status =
      json
      |> Map.fetch!("data")
      |> Map.fetch!("stations")

    features =
      stations_geojson
      |> Map.fetch!("features")
      |> Enum.map(fn s ->
        station_id = s["properties"]["station_id"]

        status =
          station_status
          |> Enum.find(fn s -> s["station_id"] == station_id end)
          |> Map.delete("station_id")

        put_in(s["properties"]["station_status"], status)
      end)

    %{
      "type" => "FeatureCollection",
      "features" => features
    }
  end

  def add_free_bike_status(resp_data, payload) do
    payload
    |> feed_url_from_payload("free_bike_status")
    |> case do
      nil ->
        resp_data

      url ->
        geojson = free_bike_status_geojson(url)
        resp_data |> Map.put("free_floating", geojson)
    end
  rescue
    _e -> resp_data
  end

  def free_bike_status_geojson(url) do
    json = fetch_gbfs_endpoint!(url)

    vehicles =
      json
      |> Map.fetch!("data")
      |> Map.fetch!("bikes")

    features =
      vehicles
      |> Enum.filter(fn v -> v["station_id"] |> is_nil() end)
      |> Enum.map(fn v ->
        %{
          "type" => "Feature",
          "geometry" => %{
            "type" => "Point",
            "coordinates" => [v["lon"], v["lat"]]
          },
          "properties" => Map.drop(v, ["lat", "lon"])
        }
      end)

    %{
      "type" => "FeatureCollection",
      "features" => features
    }
  end

  def add_geofencing_zones(resp_data, payload) do
    payload
    |> feed_url_from_payload("geofencing_zones")
    |> case do
      nil ->
        resp_data

      url ->
        geojson = geofencing_zones_geojson(url)
        resp_data |> Map.put("geofencing_zones", geojson)
    end
  rescue
    _e -> resp_data
  end

  def geofencing_zones_geojson(url) do
    json = fetch_gbfs_endpoint!(url)

    zones =
      json
      |> Map.fetch!("data")
      |> Map.fetch!("geofencing_zones")
  end

  defp fetch_gbfs_endpoint!(url) do
    %{status_code: 200, body: body} = http_client().get!(url)
    Jason.decode!(body)
  end

  defp feed_url_from_payload(payload, feed_name) do
    payload |> GBFSMetadata.first_feed() |> GBFSMetadata.feed_url_by_name(feed_name)
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
