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
    :nom_commune,
    :insee_commune_principale,
    :nombre_communes,
    :population
  ]

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params), do: render(conn, "index.html", aoms: aoms())

  @spec prepare_aom({AOM.t(), binary()}, list(), list()) :: map()
  defp prepare_aom({aom, nom_commune}, datasets, aggregated_datasets) do
    all_datasets = datasets ++ aggregated_datasets

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
      |> join(:left, [dataset: d], aom in AOM, on: d.aom_id == aom.id, as: :aom)
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
      |> Repo.all()

    datasets |> Enum.group_by(& &1.dataset_id) |> Map.values |> Enum.map(&length/1) |> Enum.max |> dbg(label: "size of each group")

    datasets_by_aom_id = datasets |> Enum.group_by(& &1.aom_id)
    dataset_by_dataset_id = datasets |> Map.new(&{&1.dataset_id, &1})

    # dbg(datasets_by_dataset_id, label: "datasets_by_datasets_id")
    # Datasets with a key dataset to find them easily. The AOM ID inside is AOM as territory.
    # datasets_by_dataset_id #=> %{
    #   518 => [%{aom_id: nil, dataset_id: 518, end_date: xxx, has_realtime: true}],
    #   401 => [%{aom_id: 950, dataset_id: 401, has_realtime: false}],
    #   117 => [%{aom_id: 107, dataset_id: 117, has_realtime: false}],
    #   377 => [%{aom_id: nil, dataset_id: 377, has_realtime: true}],

    repo_results =
      AOM
      |> join(:inner, [aom], d in assoc(aom, :legal_owners_dataset), as: :legal_owners_dataset)
      |> where(
        [legal_owners_dataset: d],
        d.id in subquery(
          Dataset.base_query()
          |> join(:inner, [dataset: d], aom in assoc(d, :legal_owners_aom), as: :aom)
          |> group_by([dataset: d], d.id)
          |> having([aom: a], count(a.id) >= 2)
          |> select([dataset: d], d.id)
        )
      )
      |> select([aom, legal_owners_dataset: d], %{aom_id: aom.id, dataset_id: d.id})
      |> Repo.all()

      # List of tupples AOM / Legal owner dataset but as in the subquery we limit to only one dataset per AOM ? No.
      dbg(repo_results, label: "repo_results")
      # repo_results #=> [
      #   %{aom_id: 5, dataset_id: 787},
      #   %{aom_id: 9, dataset_id: 732},
      #   %{aom_id: 15, dataset_id: 787},
      #   %{aom_id: 17, dataset_id: 976},
      #   %{aom_id: 19, dataset_id: 146},

      repo_results |> Enum.group_by(& &1.aom_id) |> Map.values |> Enum.map(&length/1) |> Enum.max |> dbg(label: "size of each group")

      aggregated_datasets =
      repo_results
      |> Enum.group_by(& &1.aom_id, fn %{dataset_id: dataset_id} ->
        dataset_by_dataset_id |> Map.get(dataset_id, %{})
      end)

    dbg(aggregated_datasets, label: "aggregated_datasets")
    # We take back the list of AOMS from the repo result, and enrich it
    # aggregated_datasets #=> %{
    # 289 => [%{aom_id: nil, dataset_id: 732, has_realtime: false}],
    # 309 => [%{aom_id: nil, dataset_id: 732, has_realtime: false}],
    # 704 => [%{aom_id: nil, dataset_id: 176, has_realtime: false}],
    # 621 => [%{aom_id: nil, dataset_id: 979, has_realtime: false}],
    # 219 => [%{aom_id: nil, dataset_id: 38, has_realtime: false}],
    # 492 => [%{aom_id: nil, dataset_id: 979, has_realtime: false}],
    # 311 => [%{aom_id: nil, dataset_id: 176, has_realtime: false}],

    AOM
    |> join(:left, [aom], c in Commune, on: aom.insee_commune_principale == c.insee)
    |> preload([:region])
    |> select([aom, commune], {aom, commune.nom})
    |> Repo.all()
    |> Enum.map(fn {aom, nom_commune} ->
      prepare_aom({aom, nom_commune}, Map.get(datasets_by_aom_id, aom.id, []), Map.get(aggregated_datasets, aom.id, []))
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
