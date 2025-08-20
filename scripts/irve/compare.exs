#
# This script helps us detect IRVE resources
# which are in data gouv, but not in our raw consolidation
# (so that we can correct the delta & ensure our consolidation is as complete as possible)
#
# First you'll need to run the following script to download both data gouv aggregate & ours.
#
# `elixir run scripts/irve/stats.exs`
#
# Then:
#
# `mix run scripts/irve/compare.exs`
#

file_1 = "cache-dir/consolidation-data-gouv.csv"
file_2 = "cache-dir/consolidation-pan.csv"

defmodule Compare do
  def load_file!(file) do
    Explorer.DataFrame.from_csv!(file, infer_schema_length: nil)
  end

  def identifiers(df) do
    df["id_pdc_itinerance"]
    |> Explorer.Series.distinct()
    |> Explorer.Series.to_list()
    |> MapSet.new()
  end

  require Explorer.DataFrame

  def look_up_missing(df, identifiers) do
    identifiers = identifiers |> MapSet.to_list()

    df
    |> Explorer.DataFrame.filter(id_pdc_itinerance in ^identifiers)
    |> Explorer.DataFrame.group_by([:datagouv_dataset_id])
    |> Explorer.DataFrame.summarise(unique_count: n_distinct(id_pdc_itinerance))
    |> Explorer.DataFrame.sort_by(desc: unique_count)
  end
end

df1 = Compare.load_file!(file_1)
df2 = Compare.load_file!(file_2)

# out-of-explorer compare ; not the most efficient, but will do for a local compare
d1 = Compare.identifiers(df1)
d2 = Compare.identifiers(df2)

MapSet.intersection(d1, d2) |> Enum.count() |> IO.inspect(label: "unique identifiers found in both")
MapSet.difference(d1, d2) |> Enum.count() |> IO.inspect(label: "unique identifiers only in #{file_1}")
MapSet.difference(d2, d1) |> Enum.count() |> IO.inspect(label: "unique identifiers only in #{file_2}")

Compare.look_up_missing(df1, MapSet.difference(d1, d2))
|> IO.inspect(IEx.inspect_opts())
