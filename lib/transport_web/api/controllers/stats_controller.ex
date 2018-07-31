defmodule TransportWeb.API.StatsController do
  use TransportWeb, :controller

  def geojson do
    %{
      "type" => "FeatureCollection",
      "name" => "Autorités organisatrices de Mobiltés",
      "features" => features()
    }
  end

  def features do
    :mongo
    |> Mongo.aggregate(
      "aoms",
      [%{"$lookup" => %{
        "from" => "datasets",
        "localField" => "properties.liste_aom_Code INSEE Commune Principale",
        "foreignField" => "commune_principale",
        "as" => "datasets"
      }}],
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
    render(conn, %{data: geojson()})
  end
end
