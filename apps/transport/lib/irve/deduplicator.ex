defmodule Transport.IRVE.Deduplicator do
  @moduledoc """
  A module to deduplicate IRVE valid PDCs in the database, taking as an entry point
  the dataframe from the `Transport.IRVE.DatabaseExporter` module.
  """

  require Explorer.DataFrame

  @doc """
  Takes in entry a dataframe of IRVE valid PDCs,
  and returns a dataframe with an additional column "deduplication_status" with information about the duplicates.
  Values of the additional column:
  - unique
  - kept_because_more_recent
  - removed_because_not_more_recent
  """
  def add_duplicates_column(df) do
    # TODO at one point: deal with non_concerné and such.
    Explorer.DataFrame.group_by(df, "id_pdc_itinerance")
    |> Explorer.DataFrame.mutate(similar_pdc_count: count(datagouv_resource_id))
    |> Explorer.DataFrame.mutate(max_datagouv_last_modified: max(datagouv_last_modified))
    |> Explorer.DataFrame.mutate(
      deduplication_status:
        cond do
          similar_pdc_count == 1 ->
            "unique"

          datagouv_last_modified == max_datagouv_last_modified ->
            "kept_because_more_recent"

          true ->
            "removed_because_not_more_recent"
        end
    )
    |> Explorer.DataFrame.discard("similar_pdc_count")
    |> Explorer.DataFrame.discard("max_datagouv_last_modified")
    |> Explorer.DataFrame.ungroup()
  end
end
