defmodule TransportWeb.AOMSController do
  use TransportWeb, :controller
  alias DB.{AOM, Commune, Repo, Resource}
  import Ecto.Query

  def index(conn, _params) do
    aoms = AOM
    |> preload([:datasets, :region, :parent_dataset])
    |> preload([datasets: :resources])
    |> join(:left, [aom], c in Commune, on: aom.insee_commune_principale == c.insee)
    |> select([aom, commune], [aom, commune.nom])
    |> Repo.all()
    |> Enum.map(&prepare_aom/1)

    conn
     |> render("index.html", aoms: aoms)
  end

  defp prepare_aom([aom, nom_commune]) do
    %{
      nom: aom.nom,
      departement: aom.departement,
      region: (if aom.region, do: aom.region.nom, else: ""),
      published: self_published(aom) || !is_nil(aom.parent_dataset),
      in_aggregate: !is_nil(aom.parent_dataset),
      up_to_date: up_to_date?(aom.datasets),
      population_muni_2014: aom.population_muni_2014,
      nom_commune: nom_commune,
      insee_commune_principale: aom.insee_commune_principale,
      nombre_communes: aom.nombre_communes,
      has_realtime: Enum.any?(aom.datasets, fn d -> d.has_realtime end),
    }
  end

  defp self_published(aom) do
    !(aom.datasets
    |> Enum.filter(fn d -> d.type == "public-transit" end)
    |> Enum.empty?)
  end

  defp valid_dataset?(dataset), do: Enum.any?(dataset.resources, fn r -> !Resource.is_outdated?(r) end)

  defp up_to_date?([]), do: nil
  defp up_to_date?(datasets), do: Enum.any?(datasets, &valid_dataset?/1)

end
