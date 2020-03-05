defmodule TransportWeb.AOMSController do
  use TransportWeb, :controller
  alias DB.{AOM, Commune, Dataset, Repo, Resource}
  import Ecto.Query

  @csvheaders [
    :nom,
    :departement,
    :region,
    :published,
    :in_aggregate,
    :up_to_date,
    :has_realtime,
    :population_muni_2014,
    :nom_commune,
    :insee_commune_principale,
    :nombre_communes
  ]

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params), do: render(conn, "index.html", aoms: aoms())

  @spec prepare_aom({AOM.t(), binary()}) :: map()
  defp prepare_aom({aom, nom_commune}) do
    %{
      nom: aom.nom,
      departement: aom.departement,
      region: if(aom.region, do: aom.region.nom, else: ""),
      published: self_published(aom) || !is_nil(aom.parent_dataset),
      in_aggregate: !is_nil(aom.parent_dataset),
      up_to_date: up_to_date?(aom.datasets, aom.parent_dataset),
      population_muni_2014: aom.population_muni_2014,
      nom_commune: nom_commune,
      insee_commune_principale: aom.insee_commune_principale,
      nombre_communes: aom.nombre_communes,
      has_realtime: Enum.any?(aom.datasets, fn d -> d.has_realtime end)
    }
  end

  @spec csv(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def csv(conn, _params) do
    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"autorités_organisatrices_des_mobilités.csv\"")
    |> send_resp(200, csv_content())
  end

  @spec aoms :: [map()]
  defp aoms do
    AOM
    |> preload([:datasets, :region, :parent_dataset])
    |> preload(datasets: :resources)
    |> preload(parent_dataset: :resources)
    |> join(:left, [aom], c in Commune, on: aom.insee_commune_principale == c.insee)
    |> select([aom, commune], {aom, commune.nom})
    |> Repo.all()
    |> Enum.map(&prepare_aom/1)
  end

  @spec self_published(AOM.t()) :: boolean
  defp self_published(aom) do
    !(aom.datasets
      |> Enum.filter(fn d -> d.type == "public-transit" end)
      |> Enum.empty?())
  end

  @spec valid_dataset?(Dataset.t()) :: boolean()
  defp valid_dataset?(dataset), do: Enum.any?(dataset.resources, fn r -> !Resource.is_outdated?(r) end)

  @spec up_to_date?([Dataset.t()], Dataset.t() | nil) :: boolean()
  defp up_to_date?([], nil), do: false
  defp up_to_date?([], parent), do: up_to_date?([parent], nil)

  defp up_to_date?(datasets, _parent) do
    datasets
    |> Enum.filter(fn d -> d.type == "public-transit" end)
    |> case do
      [] -> false
      transit_datasets -> Enum.any?(transit_datasets, &valid_dataset?/1)
    end
  end

  @spec csv_content() :: binary()
  defp csv_content do
    aoms()
    |> CSV.encode(headers: @csvheaders)
    |> Enum.to_list()
    |> to_string
  end
end
