defmodule TransportWeb.AOMSController do
  use TransportWeb, :controller
  alias DB.{AOM, Commune, Repo, Resource}
  import Ecto.Query
  import CSV

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
    :nombre_communes,
  ]

  def index(conn, _params), do: render(conn, "index.html", aoms: aoms())

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

  def csv(conn, _params) do
    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"autorités_organisatrices_des_mobilités.csv\"")
    |> send_resp(200, csv_content())
  end

  defp aoms do
    AOM
    |> preload([:datasets, :region, :parent_dataset])
    |> preload([datasets: :resources])
    |> join(:left, [aom], c in Commune, on: aom.insee_commune_principale == c.insee)
    |> select([aom, commune], [aom, commune.nom])
    |> Repo.all()
    |> Enum.map(&prepare_aom/1)
  end

  defp self_published(aom) do
    !(aom.datasets
    |> Enum.filter(fn d -> d.type == "public-transit" end)
    |> Enum.empty?)
  end

  defp valid_dataset?(dataset), do: Enum.any?(dataset.resources, fn r -> !Resource.is_outdated?(r) end)

  defp up_to_date?([]), do: nil
  defp up_to_date?(datasets), do: Enum.any?(datasets, &valid_dataset?/1)

  defp csv_content do
    aoms()
    |> CSV.encode(headers: @csvheaders)
    |> Enum.to_list
    |> to_string
  end

end
