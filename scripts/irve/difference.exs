# mix run scripts/irve/difference.exs

require Explorer.DataFrame
import Ecto.Query

# datagouv_source = "https://www.data.gouv.fr/fr/datasets/r/eb76d20a-8501-400e-b336-d85724de5435"
local_datagouv_path = "datagouv-consolidation.csv"
# %{status: 200} = Req.get!(datagouv_source, into: File.stream!(local_datagouv_path))
# generate with `mix run dump-simple-consolidation.exs`

datagouv_df = Explorer.DataFrame.from_csv!(local_datagouv_path, infer_schema_length: nil)

list_of_datagouv_ids =
  datagouv_df["datagouv_resource_id"]
  |> Explorer.Series.distinct()
  |> Explorer.Series.to_list()
  |> MapSet.new()

list_of_simple_consolidation_ids =
  DB.IRVEValidFile
  |> Ecto.Query.select([:resource_datagouv_id])
  |> DB.Repo.all()
  |> Enum.map(& &1.resource_datagouv_id)
  |> MapSet.new()

only_in_datagouv = MapSet.difference(list_of_datagouv_ids, list_of_simple_consolidation_ids)

IO.inspect(MapSet.size(only_in_datagouv), label: "Only in datagouv consolidation")

# Not working from there
# Filter the dataframe with only the resource_datagouv_id found in only_in_datagouv
filtered_df =
  datagouv_df
  |> Explorer.DataFrame.filter(
    Explorer.Series.in("datagouv_resource_id", Explorer.Series.from_list(MapSet.to_list(only_in_datagouv)))
  )

# Group by resource_datagouv_id and count the number of lines for each id
lines_per_id =
  filtered_df
  |> Explorer.DataFrame.group_by(["datagouv_resource_id"])
  |> Explorer.DataFrame.summarise(line_count: count(datagouv_resource_id))
  |> Explorer.DataFrame.sort_by(line_count, direction: :desc)

IO.puts("\nNumber of lines per resource_datagouv_id (only those in datagouv but not in simple consolidation):")
IO.inspect(lines_per_id)
