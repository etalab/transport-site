defmodule TransportWeb.AOMSController do
  use TransportWeb, :controller
  alias DB.{AOM, Commune, Dataset, Repo}
  import Ecto.Query

  @csvheaders [
    :nom,
    :departement,
    :region,
    :published,
    :in_aggregate,
    :up_to_date,
    :has_realtime,
    :population_municipale,
    :nom_commune,
    :insee_commune_principale,
    :nombre_communes
  ]

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params), do: render(conn, "index.html", aoms: aoms())

  @spec prepare_aom({AOM.t(), binary()}, list(), Dataset.t() | nil) :: map()
  defp prepare_aom({aom, nom_commune}, datasets, parent_dataset) do
    published =
      case {datasets, parent_dataset} do
        {[], nil} -> false
        _ -> true
      end

    all_datasets =
      case parent_dataset do
        nil -> datasets
        parent_dataset -> datasets ++ [parent_dataset]
      end

    datasets_up_to_date =
      all_datasets
      |> Enum.reject(& is_nil(&1.end_date))
      |> Enum.any?(fn dataset -> Date.compare(dataset.end_date, Date.utc_today()) !== :lt end)

    datasets_realtime = Enum.any?(all_datasets, fn dataset -> dataset.has_realtime end)

    %{
      nom: aom.nom,
      departement: aom.departement,
      region: if(aom.region, do: aom.region.nom, else: ""),
      published: published,
      in_aggregate: !is_nil(parent_dataset),
      up_to_date: datasets_up_to_date,
      population_municipale: aom.population_municipale,
      nom_commune: nom_commune,
      insee_commune_principale: aom.insee_commune_principale,
      nombre_communes: aom.nombre_communes,
      has_realtime: datasets_realtime
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
  def aoms do
    query =
      Dataset.base_query()
      |> Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
      |> where([dataset: d], d.type == "public-transit")
      |> select(
        [dataset: d, metadata: m],
        {as(:aom).id,
         %{
           dataset_id: d.id,
           end_date: fragment("TO_DATE(?->>'end_date', 'YYYY-MM-DD')", m.metadata),
           has_realtime: d.has_realtime
         }}
      )

    datasets =
      query
      |> join(:inner, [dataset: d], aom in AOM, on: d.aom_id == aom.id, as: :aom)
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    parent_dataset =
      query
      |> join(:inner, [dataset: d], aom in AOM, on: d.id == aom.parent_dataset_id, as: :aom)
      |> Repo.all()
      |> Enum.into(%{})

    AOM
    |> join(:left, [aom], c in Commune, on: aom.insee_commune_principale == c.insee)
    |> preload([:region])
    |> select([aom, commune], {aom, commune.nom})
    |> Repo.all()
    |> Enum.map(fn {aom, nom_commune} ->
      prepare_aom({aom, nom_commune}, Map.get(datasets, aom.id, []), Map.get(parent_dataset, aom.id))
    end)
  end

  @spec csv_content() :: binary()
  defp csv_content do
    aoms()
    |> CSV.encode(headers: @csvheaders)
    |> Enum.to_list()
    |> to_string
  end
end
