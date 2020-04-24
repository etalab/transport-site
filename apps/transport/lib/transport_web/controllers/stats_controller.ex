defmodule TransportWeb.StatsController do
  alias DB.{AOM, Dataset, Region, Repo, Resource}
  alias Transport.CSVDocuments
  import Ecto.Query
  require Logger
  use TransportWeb, :controller

  @spec index(Plug.Conn.t(), any) :: Plug.Conn.t()
  def index(conn, _params) do
    aoms =
      Repo.all(
        from(a in AOM,
          select: %{
            population: a.population_totale_2014,
            region_id: a.region_id,
            nb_datasets: fragment("SELECT count(*) FROM dataset where aom_id = ?", a.id),
            parent_dataset_id: a.parent_dataset_id
          }
        )
      )

    aoms_with_datasets = aoms |> Enum.filter(&(&1.nb_datasets > 0 || !is_nil(&1.parent_dataset_id)))

    regions = Repo.all(from(r in Region, where: r.nom != "National"))

    aoms_max_severity = compute_aom_max_severity()
    total_aom_with_datasets = nb_aom_with_gtfs()

    render(conn, "index.html",
      nb_datasets: Repo.aggregate(Dataset, :count, :id),
      nb_pt_datasets: Dataset.count_by_type("public-transit"),
      nb_aoms: Enum.count(aoms),
      nb_aoms_with_data: Enum.count(aoms_with_datasets),
      nb_regions: Enum.count(regions),
      nb_regions_completed: regions |> Enum.count(fn r -> r.is_completed end),
      population_totale: get_population(aoms),
      population_couverte: get_population(aoms_with_datasets),
      ratio_aom_with_at_most_warnings: ratio_aom_with_at_most_warnings(aoms_max_severity, total_aom_with_datasets),
      ratio_aom_good_quality: ratio_aom_good_quality(aoms_max_severity, total_aom_with_datasets),
      aom_with_errors: Map.get(aoms_max_severity, "Error", 0),
      aom_with_fatal: Map.get(aoms_max_severity, "Fatal", 0),
      nb_officical_realtime: nb_officical_realtime(),
      nb_unofficical_realtime: nb_unofficical_realtime(),
      nb_reusers: nb_reusers(),
      nb_reuses: nb_reuses(),
      nb_dataset_types: nb_dataset_types(),
      nb_gtfs: count_dataset_with_format("GTFS"),
      nb_netex: count_dataset_with_format("netex"),
      nb_bss_datasets: count_dataset_with_format("gbfs"),
      nb_bikes_datasets: nb_bikes(),
      droms: ["antilles", "guyane", "mayotte", "reunion"]
    )
  end

  defp get_population(datasets) do
    datasets
    |> Enum.reduce(0, &(&1.population + &2))
    |> Kernel./(1_000_000)
    |> Kernel.round()
  end

  defp nb_officical_realtime do
    rt_datasets =
      from(d in Dataset,
        where: d.has_realtime
      )

    Repo.aggregate(rt_datasets, :count, :id)
  end

  @spec nb_bikes() :: integer
  defp nb_bikes do
    bikes_datasets =
      from(d in Dataset,
        where: d.type == "bike-sharing"
      )

    Repo.aggregate(bikes_datasets, :count, :id)
  end

  defp nb_unofficical_realtime do
    Enum.count(CSVDocuments.real_time_providers())
  end

  defp nb_dataset_types do
    Dataset
    |> select([d], count(d.type, :distinct))
    |> Repo.one()
  end

  defp nb_reusers do
    Enum.count(CSVDocuments.reusers())
  end

  defp nb_reuses do
    Repo.aggregate(Dataset, :sum, :nb_reuses)
  end

  defp count_dataset_with_format(format) do
    Resource
    |> select([r], count(r.dataset_id, :distinct))
    |> where([r], r.format == ^format)
    |> Repo.one()
  end

  @spec compute_aom_max_severity() :: %{binary() => integer()}
  defp compute_aom_max_severity do
    dt = Date.utc_today()
    # TODO: this query is wrong
    AOM
    |> join(:left, [aom], dataset in Dataset, on: dataset.id == aom.parent_dataset_id or dataset.aom_id == aom.id)
    |> join(:left, [_, dataset], _r in assoc(dataset, :resources))
    |> join(:left, [_, _, resource], _v in assoc(resource, :validation))
    |> where([_a, _d, r, _v], r.format == "GTFS")
    |> where([_a, _d, r, _v], not is_nil(r.end_date) and r.end_date >= ^dt)
    |> group_by([_a, _d, _r, v], v.max_error)
    |> select([a, d, r, v], %{
      count: count(v.max_error),
      error: v.max_error
    })
    |> Repo.all()
    |> Enum.map(fn %{count: count, error: error} -> {error, count} end)
    |> Map.new()
    |> IO.inspect
  end

  @spec ratio_aom_with_at_most_warnings(integer(), integer()) :: integer()
  defp ratio_aom_with_at_most_warnings(aom_max_severity, 0) do
    0
  end

  defp ratio_aom_with_at_most_warnings(aom_max_severity, nb_aom_with_data) do
    sum =
      Map.get(aom_max_severity, "Warning", 0) +
        Map.get(aom_max_severity, "Information", 0) +
        Map.get(aom_max_severity, "Irrelevant", 0) +
        Map.get(aom_max_severity, "NoError", 0)
    (sum / nb_aom_with_data *
       100)
    |> round
  end

  @spec ratio_aom_good_quality(%{binary() => integer()}, integer()) :: integer()
  defp ratio_aom_good_quality(aom_max_severity, 0) do
    0
  end

  defp ratio_aom_good_quality(aom_max_severity, nb_aom_with_data) do
    sum =
      Map.get(aom_max_severity, "Information", 0) +
      Map.get(aom_max_severity, "Irrelevant", 0) +
      Map.get(aom_max_severity, "NoError", 0)

      (sum *
      100 /
      nb_aom_with_data)
      |> round
    end

  @spec nb_aom_with_gtfs() :: integer()
  defp nb_aom_with_gtfs() do
    resources =
      Resource
      |> where([r], not is_nil(r.end_date))
      |> where([r], r.format == "GTFS")
      |> group_by([r], r.dataset_id)
      |> distinct([r], r.dataset_id)
      |> select([r], %{dataset_id: r.dataset_id})

    datasets = Dataset
    |> join(:right, [d], r in subquery(resources), on: d.id == r.dataset_id)
    |> select([d, _r], %{id: d.id, aom_id: d.aom_id})

    AOM
    |> join(:right, [a], d in subquery(datasets), on: d.aom_id == a.id or d.id == a.parent_dataset_id)
    |> select([a, _d], a.id)
    |> Repo.aggregate(:count, :id)
    |> IO.inspect()
  end
end
