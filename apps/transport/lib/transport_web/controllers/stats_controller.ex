defmodule TransportWeb.StatsController do
  alias DB.{AOM, Dataset, Region, Repo, Resource, Validation}
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

    total_aom_with_datasets =
      aoms_max_severity
      |> Map.values()
      |> Enum.filter(fn error -> not is_nil(error) end)
      |> Enum.sum()

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
      nb_netex: count_dataset_with_format("NeTEx"),
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
        where: d.has_realtime and d.is_active and d.type == "public-transit"
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
    # consolidate the maximum error for the current dataset for each dataset
    # return, for each error, the number of AOM with this maximum error
    dt = Date.utc_today()

    validations =
      Validation
      |> select([v], %{
        max_error:
          fragment("""
          CASE max_error::text
          WHEN 'Fatal' THEN 5
          WHEN 'Error' THEN 4
          WHEN 'Warning' THEN 3
          WHEN 'Information' THEN 2
          WHEN 'Irrelevant' THEN 1
          ELSE 0
          END
          """),
        resource_id: v.resource_id
      })

    AOM
    |> join(:left, [aom], dataset in Dataset, on: dataset.id == aom.parent_dataset_id or dataset.aom_id == aom.id)
    |> join(:left, [_, dataset], _r in assoc(dataset, :resources))
    |> join(:left, [_, _, r], v in subquery(validations), on: v.resource_id == r.id)
    |> where([_a, _d, r, _v], r.format == "GTFS")
    |> where([_a, _d, r, _v], r.end_date >= ^dt)
    |> group_by([_a, _d, _r, v], _a.id)
    |> select([a, d, r, v], %{
      aom: a.id,
      max_error: max(v.max_error)
    })
    |> Repo.all()
    |> List.foldl(%{}, fn %{max_error: max_error}, acc ->
      max_error =
        case max_error do
          5 -> "Fatal"
          4 -> "Error"
          3 -> "Warning"
          2 -> "Information"
          1 -> "Irrelevant"
          0 -> "NoError"
          _ -> nil
        end

      Map.update(acc, max_error, 0, fn v -> v + 1 end)
    end)
  end

  @spec ratio_aom_with_at_most_warnings(%{binary() => integer()}, integer()) :: integer()
  defp ratio_aom_with_at_most_warnings(_aom_max_severity, 0) do
    0
  end

  defp ratio_aom_with_at_most_warnings(aom_max_severity, nb_aom_with_data) do
    sum =
      Map.get(aom_max_severity, "Warning", 0) +
        Map.get(aom_max_severity, "Information", 0) +
        Map.get(aom_max_severity, "Irrelevant", 0) +
        Map.get(aom_max_severity, "NoError", 0)

    round(sum / nb_aom_with_data * 100)
  end

  @spec ratio_aom_good_quality(%{binary() => integer()}, integer()) :: integer()
  defp ratio_aom_good_quality(_aom_max_severity, 0) do
    0
  end

  defp ratio_aom_good_quality(aom_max_severity, nb_aom_with_data) do
    sum =
      Map.get(aom_max_severity, "Information", 0) +
        Map.get(aom_max_severity, "Irrelevant", 0) +
        Map.get(aom_max_severity, "NoError", 0)

    round(sum * 100 / nb_aom_with_data)
  end
end
