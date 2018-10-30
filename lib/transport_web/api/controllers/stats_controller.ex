defmodule TransportWeb.API.StatsController do
  use TransportWeb, :controller
  alias Transport.ReusableData.Dataset

  def geojson(features) do
    %{
      "type" => "FeatureCollection",
      "name" => "Autorités organisatrices de Mobiltés",
      "features" => features
    }
  end

  def features(collection_name, lookup) do
    :mongo
    |> Mongo.aggregate(
      collection_name,
      [lookup],
      pool: DBConnection.Poolboy
    )
    |> Enum.map(fn %{"geometry" => geom, "type" => type, "properties" => properties, "datasets" => datasets} -> %{
      "geometry" => geom,
      "type" => type,
      "properties" => Map.put(properties, "dataset_count", Enum.count datasets)
    } end)
    |> Enum.to_list
  end

  def index(%Plug.Conn{} = conn, _params) do
    render(conn, %{data: geojson(features("aoms", Dataset.aoms_lookup))})
  end

  def regions(%Plug.Conn{} = conn, _params) do
    render(conn, %{data: geojson(features("regions", Dataset.regions_lookup))})
  end
end
