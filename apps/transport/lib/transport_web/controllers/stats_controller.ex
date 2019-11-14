defmodule TransportWeb.StatsController do
  alias DB.{AOM, Dataset, Region, Repo}
  import Ecto.Query
  require Logger
  use TransportWeb, :controller
  alias Transport.CSVDocuments

  @spec index(any, any) :: none
  def index(conn, _params) do
    aoms = Repo.all(from a in AOM,
      select: %{
        population: a.population_totale_2014,
        region_id: a.region_id,
        nb_datasets: fragment("SELECT count(*) FROM dataset where aom_id = ?", a.id),
        parent_dataset_id: a.parent_dataset_id,
      }
    )
    aoms_with_datasets = aoms |> Enum.filter(&(&1.nb_datasets > 0 || !is_nil(&1.parent_dataset_id)))

    regions = Repo.all(from r in Region, where: r.nom != "National")

    render(conn, "index.html",
      nb_datasets: Repo.aggregate(Dataset, :count, :id),
      nb_aoms: Enum.count(aoms),
      nb_aoms_with_data: Enum.count(aoms_with_datasets),
      nb_regions: Enum.count(regions),
      nb_regions_completed: regions |> Enum.count(fn r -> r.is_completed end),
      population_totale: get_population(aoms),
      population_couverte: get_population(aoms_with_datasets),
      nb_officical_realtime: nb_officical_realtime(),
      nb_unofficical_realtime: nb_unofficical_realtime()
    )
  end

  defp get_population(datasets) do
      datasets
      |> Enum.reduce(0, &(&1.population + &2))
      |> Kernel./(1_000_000)
      |> Float.round(2)
  end

  defp nb_officical_realtime do
    rt_datasets = from d in Dataset,
        where: d.has_realtime
    Repo.aggregate(rt_datasets, :count, :id)
  end

  defp nb_unofficical_realtime do
    Enum.count(CSVDocuments.real_time_providers())
  end

end
