defmodule TransportWeb.StatsController do
  alias Transport.ReusableData
  alias Transport.ReusableData.Dataset
  use TransportWeb, :controller

  defp has_dataset?(aom), do: !Enum.empty?(Map.get(aom, "datasets", []))
  defp is_completed?(region), do: Map.get(Map.get(region, "properties", %{}), "completed", false)

  def index(conn, _params) do
    aoms = Mongo.aggregate(
      :mongo,
      "aoms",
      [Dataset.aoms_lookup],
      pool: DBConnection.Poolboy
    )
    regions = Mongo.aggregate(
      :mongo,
      "regions",
      [Dataset.regions_lookup],
      pool: DBConnection.Poolboy
    )
    render(conn, "index.html",
     nb_datasets: Enum.count(ReusableData.list_datasets),
     nb_aoms: Enum.count(aoms),
     nb_aoms_with_data: aoms |> Enum.filter(&has_dataset?/1) |> Enum.count,
     nb_regions: Enum.count(regions),
     nb_regions_completed: regions |> Enum.filter(&is_completed?/1) |> Enum.count
    )
  end
end
