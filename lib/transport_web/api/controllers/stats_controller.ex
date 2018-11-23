defmodule TransportWeb.API.StatsController do
  use TransportWeb, :controller
  alias Transport.{AOM, Repo, Region}
  import Ecto.Query

  def geojson(features) do
    %{
      "type" => "FeatureCollection",
      "name" => "Autorités organisatrices de Mobiltés",
      "features" => features
    }
  end

  def features(q) do
    q
    |> Repo.all
    |> Enum.map(fn aom -> %{
      "geometry" => aom.geometry,
      "type" => "Feature",
      "properties" => %{
        "dataset_count" => Map.get(aom, :nb_datasets, 0),
        "completed" => Map.get(aom, :is_completed, false),
        "nom" => Map.get(aom, :nom, ""),
        "id" => aom.id,
        "forme_juridique" => Map.get(aom, :forme_juridique, "")
      }
    } end)
    |> Enum.to_list
  end

  def index(%Plug.Conn{} = conn, _params) do
    render(conn,
      %{
        data: geojson(features(from a in AOM, select: %{
              geometry: a.geometry,
              id: a.id,
              nb_datasets: fragment("SELECT COUNT(*) FROM dataset WHERE aom_id=?", a.id),
              nom: a.nom,
              forme_juridique: a.forme_juridique
            }))})
  end

  def regions(%Plug.Conn{} = conn, _params) do
    render(conn, %{data: geojson(features(from r in Region, select: %{
      geometry: r.geometry,
      id: r.id,
      nom: r.nom,
      is_completed: r.is_completed,
      nb_datasets: fragment("SELECT COUNT(*) FROM dataset WHERE region_id=?", r.id)
    }))})
  end
end
