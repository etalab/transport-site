defmodule Transport.GbfsToGeojson do
  @moduledoc """
  Converts a GBFS feed to useful GeoJSONs
  """
  alias Transport.GBFSMetadata

  @doc """
  Main module function: returns a map of geojsons generated from the GBFS endpoint
  """
  @spec gbfs_geojsons(binary()) :: map()
  def gbfs_geojsons(url) do
    payload = fetch_gbfs_endpoint!(url)

    %{}
    |> add_station_information(payload)
    |> add_station_status(payload)
    |> add_free_bike_status(payload)
    |> add_geofencing_zones(payload)
  end

  @spec add_station_information(map(), map()) :: map()
  defp add_station_information(resp_data, payload) do
    payload
    |> feed_url_from_payload("station_information")
    |> case do
      nil ->
        resp_data

      url ->
        geojson = station_information_geojson!(url)
        resp_data |> Map.put("stations", geojson)
    end
  rescue
    _e -> resp_data
  end

  @spec station_information_geojson!(binary()) :: map()
  defp station_information_geojson!(url) do
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

  @spec add_station_status(map(), map()) :: map()
  defp add_station_status(%{"stations" => stations_geojson} = resp_data, payload) do
    payload
    |> feed_url_from_payload("station_status")
    |> case do
      nil ->
        resp_data

      url ->
        geojson = url |> station_status_geojson!(stations_geojson)
        resp_data |> Map.put("stations", geojson)
    end
  rescue
    _e -> resp_data
  end

  defp add_station_status(resp_data, _payload) do
    resp_data
  end

  @spec station_status_geojson!(binary(), map()) :: map()
  defp station_status_geojson!(station_status_url, stations_geojson) do
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

  @spec add_free_bike_status(map(), map()) :: map()
  defp add_free_bike_status(resp_data, payload) do
    payload
    |> feed_url_from_payload("free_bike_status")
    |> case do
      nil ->
        resp_data

      url ->
        geojson = free_bike_status_geojson!(url)
        resp_data |> Map.put("free_floating", geojson)
    end
  rescue
    _e -> resp_data
  end

  @spec free_bike_status_geojson!(binary()) :: map()
  defp free_bike_status_geojson!(url) do
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

  @spec add_geofencing_zones(map(), map()) :: map()
  defp add_geofencing_zones(resp_data, payload) do
    payload
    |> feed_url_from_payload("geofencing_zones")
    |> case do
      nil ->
        resp_data

      url ->
        geojson = geofencing_zones_geojson!(url)
        resp_data |> Map.put("geofencing_zones", geojson)
    end
  rescue
    _e -> resp_data
  end

  @spec geofencing_zones_geojson!(binary()) :: map()
  defp geofencing_zones_geojson!(url) do
    url
    |> fetch_gbfs_endpoint!()
    |> Map.fetch!("data")
    |> Map.fetch!("geofencing_zones")
  end

  @spec fetch_gbfs_endpoint!(binary()) :: map()
  defp fetch_gbfs_endpoint!(url) do
    %{status_code: 200, body: body} = http_client().get!(url)
    Jason.decode!(body)
  end

  @spec feed_url_from_payload(map(), binary()) :: binary()
  defp feed_url_from_payload(payload, feed_name) do
    payload |> GBFSMetadata.first_feed() |> GBFSMetadata.feed_url_by_name(feed_name)
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
