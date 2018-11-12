defmodule TransportWeb.StatsController do
  alias Transport.ReusableData
  alias Transport.ReusableData.Dataset
  require Logger
  use TransportWeb, :controller

  def index(conn, _params) do
    aoms = Mongo.aggregate(
      :mongo,
      "aoms",
      [Dataset.aoms_lookup,
      %{
        "$project" => %{
          "datasets" => 1,
          "properties" => %{"liste_aom_Nouvelles régions" => 1, "liste_aom_Population Totale 2014" => 1}
          }
        }
      ],
      pool: DBConnection.Poolboy
    )
    aoms_with_datasets = aoms |> Enum.filter(&(has_dataset?(&1) || is_bretagne?(&1)))

    regions = Mongo.aggregate(
      :mongo,
      "regions",
      [Dataset.regions_lookup,
      %{"$project" => %{"properties" => 1}}],
      pool: DBConnection.Poolboy
    )

    render(conn, "index.html",
     nb_datasets: Enum.count(ReusableData.list_datasets(projection: %{"_id" => 1})),
     nb_aoms: Enum.count(aoms),
     nb_aoms_with_data: Enum.count(aoms_with_datasets),
     nb_regions: Enum.count(regions),
     nb_regions_completed: regions |> Enum.filter(&is_completed?/1) |> Enum.count,
     population_totale: get_population(aoms),
     population_couverte: get_population(aoms_with_datasets)
    )
  end

  defp is_bretagne?(aom), do: fetch_property(aom, "liste_aom_Nouvelles régions") == {:ok, "Bretagne"}
  defp has_dataset?(aom), do: !Enum.empty?(Map.get(aom, "datasets", []))
  defp is_completed?(region), do: fetch_property(region, "completed") == {:ok, true}

  defp get_population(datasets) do
      datasets
      |> Enum.reduce(0, &(parse_population(&1) + &2))
      |> Kernel./(1000)
      |> Float.round(2)
  end

  defp parse_population(aom) do
    with {:ok, population} <- fetch_property(aom, "liste_aom_Population Totale 2014"),
         {int, _} <- Integer.parse(population)
    do
      int
    else
      _ ->
        Logger.info("Unable to parse population for #{aom}")
        0
    end
  end

  defp fetch_property(map, property) do
    map
    |> Map.get("properties", %{})
    |> Map.fetch(property)
  end
end
