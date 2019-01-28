defmodule TransportWeb.API.StatsController do
  use TransportWeb, :controller
  alias Transport.{AOM, Dataset, Region, Repo}
  import Ecto.Query
  alias Geo.JSON

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
    |> Enum.filter(fn aom -> !is_nil(aom.geometry) end)
    |> Enum.map(fn aom -> %{
      "geometry" => aom.geometry |> JSON.encode!,
      "type" => "Feature",
      "properties" => %{
        "dataset_count" => Map.get(aom, :nb_datasets, 0),
        "completed" => Map.get(aom, :is_completed, false),
        "nom" => Map.get(aom, :nom, ""),
        "id" => aom.id,
        "forme_juridique" => Map.get(aom, :forme_juridique, ""),
        "parent_dataset_slug" => Map.get(aom, :parent_dataset_slug, ""),
        "parent_dataset_name" => Map.get(aom, :parent_dataset_name, "")
      }
    } end)
    |> Enum.to_list
  end

  def index(%Plug.Conn{} = conn, _params) do
    render(conn,
      %{
        data: geojson(features(
          from a in AOM,
            left_join: d in Dataset,
            on: d.id == a.parent_dataset_id,
            select: %{
              geometry: a.geom,
              id: a.id,
              nb_datasets: fragment("SELECT COUNT(*) FROM dataset WHERE aom_id=?", a.id),
              nom: a.nom,
              forme_juridique: a.forme_juridique,
              parent_dataset_slug: d.slug,
              parent_dataset_name: d.title
            }
            ))
        })
  end

  def regions(%Plug.Conn{} = conn, _params) do
    render(conn, %{data: geojson(features(from r in Region, select: %{
      geometry: r.geom,
      id: r.id,
      nom: r.nom,
      is_completed: r.is_completed,
      nb_datasets: fragment("SELECT COUNT(*) FROM dataset WHERE region_id=? OR aom_id IN (SELECT id from aom WHERE region_id=?)", r.id, r.id)
    }))})
  end
end
