defmodule Transport.GbfsToGeojson do
  @moduledoc """
  Converts a GBFS feed to useful GeoJSONs
  """
  alias Transport.GBFSMetadata

  def fetch_gbfs_endpoint(url) do
    with {:ok, %{status_code: 200, body: body}} <- http_client().get(url),
         {:ok, json} <- Jason.decode(body) do
      {:ok, json}
    else
      e -> {:error, "could not fetch gbfs content at #{url}"}
    end
  end

  def station_information_geojson(url) do
    {:ok, json} = fetch_gbfs_endpoint(url)
    convert_station_information!(json)
  end

  def feed_url_from_payload(payload, feed_name) do
    payload |> GBFSMetadata.first_feed() |> GBFSMetadata.feed_url_by_name(feed_name)
  end

  def gbfs_geojsons(url) do
    {:ok, json} = fetch_gbfs_endpoint(url)

    station_information = case json |> feed_url_from_payload("station_information") do
      nil -> nil
      url -> station_information_geojson(url)
    end

    %{"stations" => station_information}
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
