# mix run scripts/irve/difference.exs

require Explorer.DataFrame

local_datagouv_path = "cache-dir/consolidation-data-gouv.csv"
local_transport_consolidation_path = "consolidation_transport_avec_doublons_irve_statique.csv"

datagouv_df = Explorer.DataFrame.from_csv!(local_datagouv_path, infer_schema_length: nil)

transport_df = Explorer.DataFrame.from_csv!(local_transport_consolidation_path, infer_schema_length: nil)

list_of_datagouv_ids =
  datagouv_df["datagouv_resource_id"]
  |> Explorer.Series.distinct()
  |> Explorer.Series.to_list()
  |> MapSet.new()

list_of_simple_consolidation_ids =
  transport_df["resource_datagouv_id"]
  |> Explorer.Series.distinct()
  |> Explorer.Series.to_list()
  |> MapSet.new()

only_in_datagouv = MapSet.difference(list_of_datagouv_ids, list_of_simple_consolidation_ids)

IO.inspect(MapSet.size(only_in_datagouv), label: "Only in datagouv consolidation")

# Filter the dataframe with only the resource_datagouv_id found in only_in_datagouv
filtered_df =
  datagouv_df
  |> Explorer.DataFrame.filter(
    Explorer.Series.in(datagouv_resource_id, Explorer.Series.from_list(MapSet.to_list(^only_in_datagouv)))
  )

# Group by resource_datagouv_id and count the number of lines for each id
lines_per_id =
  filtered_df
  |> Explorer.DataFrame.group_by(["datagouv_resource_id", "datagouv_dataset_id", "datagouv_organization_or_owner"])
  |> Explorer.DataFrame.summarise(line_count: Explorer.Series.size(datagouv_resource_id))
  |> Explorer.DataFrame.sort_by(desc: line_count)

IO.puts("\nNumber of lines per resource_datagouv_id (only those in datagouv but not in simple consolidation):")

Explorer.DataFrame.print(lines_per_id, limit: :infinity)
