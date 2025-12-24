defmodule TransportWeb.AOMSController do
  use TransportWeb, :controller
  import Ecto.Query

  @csv_headers [
    :nom,
    :departement,
    :region,
    :published,
    :in_aggregate,
    :up_to_date,
    :has_realtime,
    :nom_commune,
    :insee_commune_principale,
    :nombre_communes,
    :population,
    :nb_gtfs,
    :nb_gtfs_rt,
    :nb_netex,
    :nb_siri,
    :nb_siri_lite
  ]

  @type dataset :: %{
          required(:aom_id) => integer(),
          required(:dataset_id) => integer(),
          required(:end_date) => Date.t(),
          required(:has_realtime) => boolean()
        }

  @type aom_id :: integer()
  @type dataset_id :: integer()

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params), do: render(conn, "index.html", aoms: aoms())

  @spec prepare_aom({AOM.t(), binary()}, list(), list(), map()) :: map()
  defp prepare_aom({aom, nom_commune}, gtfs_datasets, aggregated_datasets, formats) do
    all_datasets = gtfs_datasets ++ aggregated_datasets

    datasets_up_to_date =
      all_datasets
      |> Enum.reject(&is_nil(&1.end_date))
      |> Enum.any?(fn dataset -> Date.compare(dataset.end_date, Date.utc_today()) !== :lt end)

    datasets_realtime = Enum.any?(all_datasets, fn dataset -> dataset.has_realtime end)

    %{
      nom: aom.nom,
      departement: aom.departement,
      region: if(aom.region, do: aom.region.nom, else: ""),
      published: not Enum.empty?(all_datasets),
      in_aggregate: not Enum.empty?(aggregated_datasets),
      up_to_date: datasets_up_to_date,
      population: aom.population,
      nom_commune: nom_commune,
      insee_commune_principale: aom.insee_commune_principale,
      nombre_communes: aom.nombre_communes,
      has_realtime: datasets_realtime,
      nb_gtfs: Map.get(formats, :nb_gtfs, 0),
      nb_gtfs_rt: Map.get(formats, :nb_gtfs_rt, 0),
      nb_netex: Map.get(formats, :nb_netex, 0),
      nb_siri: Map.get(formats, :nb_siri, 0),
      nb_siri_lite: Map.get(formats, :nb_siri_lite, 0)
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
    # Let’s fetch all GTFS datasets.
    # This doesn’t include GTFS-Flex, although they are in public-transit and have a GTFS format on resource.
    {gtfs_datasets_by_aom_id, gtfs_dataset_by_dataset_id} = gtfs_datasets()

    # Some AOM data is present in aggregated datasets: the region publishes on behalf of the AOM.
    # In this case, there are at least 2 legal owners on the dataset
    aggregated_datasets_by_aom_id = aggregated_datasets(gtfs_dataset_by_dataset_id)

    formats_by_aom = formats_by_aom()

    Enum.map(aoms_and_commune_principale(), fn {aom, nom_commune} ->
      prepare_aom(
        {aom, nom_commune},
        Map.get(gtfs_datasets_by_aom_id, aom.id, []),
        Map.get(aggregated_datasets_by_aom_id, aom.id, []),
        Map.get(formats_by_aom, aom.id, %{})
      )
    end)
  end

  @spec csv_content() :: binary()
  defp csv_content do
    aoms()
    |> CSV.encode(headers: @csv_headers)
    |> Enum.to_list()
    |> to_string
  end

  defp formats_by_aom do
    DB.Dataset.base_query()
    |> DB.Resource.join_dataset_with_resource()
    |> join(:left, [dataset: d], a in assoc(d, :legal_owners_aom), as: :aom)
    |> where([dataset: d], d.type == "public-transit")
    |> select(
      [aom: a, resource: r],
      %{
        aom_id: a.id,
        nb_gtfs: fragment("sum(case when ? = 'GTFS' then 1 else 0 end)", r.format),
        nb_netex: fragment("sum(case when ? = 'NeTEx' then 1 else 0 end)", r.format),
        nb_gtfs_rt: fragment("sum(case when ? = 'gtfs-rt' then 1 else 0 end)", r.format),
        nb_siri: fragment("sum(case when ? = 'SIRI' then 1 else 0 end)", r.format),
        nb_siri_lite: fragment("sum(case when ? = 'SIRI Lite' then 1 else 0 end)", r.format)
      }
    )
    |> group_by([aom: a], [a.id])
    |> DB.Repo.all()
    |> Map.new(&{&1.aom_id, &1})
  end

  @spec gtfs_datasets() :: {%{required(aom_id) => [dataset]}, %{required(dataset_id) => dataset}}
  defp gtfs_datasets do
    gtfs_datasets =
      DB.Dataset.base_query()
      |> DB.Dataset.join_from_dataset_to_metadata(
        Enum.map(Transport.ValidatorsSelection.validators_for_feature(:aoms_controller), & &1.validator_name())
      )
      |> join(:left, [dataset: d], a in assoc(d, :legal_owners_aom), as: :aom)
      |> where([dataset: d], d.type == "public-transit")
      |> select(
        [dataset: d, metadata: m, aom: a],
        %{
          aom_id: a.id,
          dataset_id: d.id,
          end_date: fragment("TO_DATE(?->>'end_date', 'YYYY-MM-DD')", m.metadata),
          has_realtime: d.has_realtime
        }
      )
      |> DB.Repo.all()

    gtfs_datasets_by_aom_id = gtfs_datasets |> Enum.group_by(& &1.aom_id)
    gtfs_dataset_by_dataset_id = gtfs_datasets |> Map.new(&{&1.dataset_id, &1})
    {gtfs_datasets_by_aom_id, gtfs_dataset_by_dataset_id}
  end

  @spec aggregated_datasets(%{required(dataset_id) => dataset}) :: %{required(aom_id) => [dataset]}
  defp aggregated_datasets(gtfs_dataset_by_dataset_id) do
    aggregated_datasets_in_db =
      DB.AOM
      |> join(:inner, [aom], d in assoc(aom, :legal_owners_dataset), as: :legal_owners_dataset)
      |> where(
        [legal_owners_dataset: d],
        d.id in subquery(
          DB.Dataset.base_query()
          |> join(:inner, [dataset: d], aom in assoc(d, :legal_owners_aom), as: :aom)
          |> DB.Resource.join_dataset_with_resource()
          |> group_by([dataset: d], d.id)
          |> having([aom: a], count(a.id, :distinct) >= 2)
          |> where([resource: r], r.format in ["GTFS", "NeTEx"])
          |> select([dataset: d], d.id)
        )
      )
      |> select([aom, legal_owners_dataset: d], %{aom_id: aom.id, dataset_id: d.id})
      |> DB.Repo.all()

    aggregated_datasets_in_db
    |> Enum.group_by(& &1.aom_id, fn %{dataset_id: dataset_id} ->
      Map.get(
        # Let’s enrich aggregated datasets with the GTFS dataset metadata if we have it
        gtfs_dataset_by_dataset_id,
        dataset_id,
        # In case of a NeTEx or GTFS-Flex dataset, we don’t have the end_date
        # We could have the realtime info by redoing the SQL query behind aggregated_datasets_in_db
        %{dataset_id: dataset_id, end_date: nil, has_realtime: false}
      )
    end)
  end

  defp aoms_and_commune_principale do
    DB.AOM
    |> join(:left, [aom], c in DB.Commune, on: aom.insee_commune_principale == c.insee)
    |> preload([:region])
    |> select([aom, commune], {aom, commune.nom})
    |> order_by([a], a.nom)
    |> DB.Repo.all()
  end
end
