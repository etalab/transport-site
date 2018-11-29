defmodule TransportWeb.StatsController do
  alias Transport.{AOM, Dataset, Region, Repo}
  import Ecto.Query
  require Logger
  use TransportWeb, :controller

  def index(conn, _params) do
    bretagne = Repo.get_by!(Region, nom: "Bretagne")
    aoms = Repo.all(from a in AOM,
      select: %{
        population: a.population_totale_2014,
        region_id: a.region_id,
        nb_datasets: fragment("SELECT count(*) FROM dataset where aom_id = ?", a.id)
      }
    )
    aoms_with_datasets = aoms |> Enum.filter(&(&1.nb_datasets > 0 || &1.region_id == bretagne.id))

    regions = Repo.all(from r in Region)

    render(conn, "index.html",
      nb_datasets: Repo.aggregate(Dataset, :count, :id),
      nb_aoms: Enum.count(aoms),
      nb_aoms_with_data: Enum.count(aoms_with_datasets),
      nb_regions: Enum.count(regions),
      nb_regions_completed: regions |> Enum.count(fn r -> r.is_completed end),
      population_totale: get_population(aoms),
      population_couverte: get_population(aoms_with_datasets)
    )
  end

  defp get_population(datasets) do
      datasets
      |> Enum.reduce(0, &(&1.population + &2))
      |> Kernel./(1_000_000)
      |> Float.round(2)
  end
end
