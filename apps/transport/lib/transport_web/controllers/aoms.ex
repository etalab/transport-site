defmodule TransportWeb.AOMSController do
  use TransportWeb, :controller
  alias DB.{AOM, Commune, Dataset, Repo}
  import Ecto.Query

  @csv_headers [
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

  @spec prepare_aom({AOM.t(), binary()}, list(), list()) :: map()
  defp prepare_aom({aom, nom_commune}, datasets, aggregated_datasets) do
    all_datasets = datasets ++ aggregated_datasets

    datasets_up_to_date =
      Enum.any?(all_datasets, fn dataset -> Date.compare(dataset.end_date, Date.utc_today()) !== :lt end)

    datasets_realtime = Enum.any?(all_datasets, fn dataset -> dataset.has_realtime end)

    %{
      nom: aom.nom,
      departement: aom.departement,
      region: if(aom.region, do: aom.region.nom, else: ""),
      published: not Enum.empty?(all_datasets),
      in_aggregate: not Enum.empty?(aggregated_datasets),
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
    datasets =
      Dataset.base_query()
      |> Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
      |> join(:inner, [dataset: d], aom in AOM, on: d.aom_id == aom.id, as: :aom)
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
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    datasets_with_multiple_aoms =
      from(a in fragment("dataset_aom_legal_owner"),
        where:
          a.dataset_id in subquery(
            from(a in fragment("dataset_aom_legal_owner"),
              group_by: a.dataset_id,
              having: count(a.aom_id) >= 2,
              select: a.dataset_id
            )
          ),
        select: %{aom_id: a.aom_id, dataset_id: a.dataset_id}
      )

    aggregated_datasets =
      AOM
      |> join(:inner, [aom], legal_owners in subquery(datasets_with_multiple_aoms), on: aom.id == legal_owners.aom_id)
      |> join(:inner, [aom, legal_owners], d in Dataset,
        on: d.id == legal_owners.dataset_id and d.is_active and d.type == "public-transit",
        as: :dataset
      )
      |> Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
      |> select(
        [aom, dataset: d, metadata: m],
        {aom.id,
         %{
           dataset_id: d.id,
           end_date: fragment("TO_DATE(?->>'end_date', 'YYYY-MM-DD')", m.metadata),
           has_realtime: d.has_realtime
         }}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    AOM
    |> join(:left, [aom], c in Commune, on: aom.insee_commune_principale == c.insee)
    |> preload([:region])
    |> select([aom, commune], {aom, commune.nom})
    |> Repo.all()
    |> Enum.map(fn {aom, nom_commune} ->
      prepare_aom({aom, nom_commune}, Map.get(datasets, aom.id, []), Map.get(aggregated_datasets, aom.id, []))
    end)
  end

  @spec csv_content() :: binary()
  defp csv_content do
    aoms()
    |> CSV.encode(headers: @csv_headers)
    |> Enum.to_list()
    |> to_string
  end
end
