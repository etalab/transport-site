defmodule TransportWeb.AOMSController do
  use TransportWeb, :controller
  alias DB.{AOM, Repo, Resource}
  import Ecto.Query

  def index(conn, _params) do
    aoms = AOM
    |> preload([:datasets, :region, :parent_dataset])
    |> preload([datasets: :resources])
    |> Repo.all()
    |> Enum.map(&prepare_aom/1)

    conn
     |> render("index.html", aoms: aoms)
  end

  defp prepare_aom(aom) do
    %{
      nom: aom.nom,
      departement: aom.departement,
      region: (if aom.region, do: aom.region.nom, else: ""),
      published: self_published(aom) || !is_nil(aom.parent_dataset),
      in_aggregate: !is_nil(aom.parent_dataset),
      up_to_date: Enum.any?(aom.datasets, &valid_dataset?/1),
      population_muni_2014: aom.population_muni_2014,
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

end
