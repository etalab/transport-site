defmodule Transport.IRVE.Deduplicator do
  @moduledoc """
  A module to deduplicate IRVE valid PDCs in the database, taking as an entry point
  the dataframe from the `Transport.IRVE.DatabaseExporter` module.
  """

  require Explorer.DataFrame

  @doc """
  Takes in entry a dataframe of IRVE valid PDCs,
  and returns a dataframe with an additional column "deduplication_status" with information about the duplicates.
  Deduplication is done on the "id_pdc_itinerance" column.
  There are multiple filters applied, and how a filter works is tricky (and depends of the previous filter):
  - Unique: if a pdc is unique, it’s written in the deduplication_status column.
  - Date_maj: for the non uniques one, we look at the max date_maj for each group of duplicates.
    - If there is only one most recent date_maj, we keep it and mark others as duplicates.
  - Datagouv_last_modified: if we cannot decide, then for dups that have the max date_maj,
    we mark as kept the one with the most recent datagouv_last_modified, and the others as duplicates.

  Values of the additional column:
  - unique
  - kept_because_date_maj_more_recent
  - removed_because_date_maj_not_more_recent
  - kept_because_resource_more_recent
  - removed_because_resource_not_more_recent
  """
  def add_duplicates_column(df) do
    # TODO at one point: deal with non_concerné and such.
    Explorer.DataFrame.group_by(df, "id_pdc_itinerance")
    |> unique_rule()
    |> date_maj_rule()
    |> datagouv_last_modified_rule()
    |> Explorer.DataFrame.ungroup()
  end

  def discard_duplicates(df) do
    df
    |> Explorer.DataFrame.filter(
      deduplication_status in ["unique", "kept_because_date_maj_more_recent", "kept_because_resource_more_recent"]
    )
    |> Explorer.DataFrame.discard("deduplication_status")
  end

  def unique_rule(df) do
    df
    |> Explorer.DataFrame.mutate(similar_pdc_count: count(datagouv_resource_id))
    |> Explorer.DataFrame.mutate(deduplication_status: if(similar_pdc_count == 1, do: "unique"))
    |> Explorer.DataFrame.discard("similar_pdc_count")
  end

  def date_maj_rule(df) do
    df
    |> Explorer.DataFrame.mutate(max_date_maj: max(date_maj))
    |> Explorer.DataFrame.mutate(is_max_date_maj: date_maj == max_date_maj)
    |> Explorer.DataFrame.group_by(["id_pdc_itinerance", "is_max_date_maj"])
    |> Explorer.DataFrame.mutate(count_is_max_date_maj: count(datagouv_resource_id))
    |> Explorer.DataFrame.mutate(
      deduplication_status:
        cond do
          is_not_nil(deduplication_status) ->
            deduplication_status

          count_is_max_date_maj > 1 ->
            nil

          is_max_date_maj and count_is_max_date_maj == 1 ->
            "kept_because_date_maj_more_recent"

          not is_max_date_maj and count_is_max_date_maj == 1 ->
            "removed_because_date_maj_not_more_recent"
        end
    )
    |> Explorer.DataFrame.discard("max_date_maj")
    |> Explorer.DataFrame.discard("count_is_max_date_maj")
    |> Explorer.DataFrame.group_by("id_pdc_itinerance")
  end

  def datagouv_last_modified_rule(df) do
    df
    |> Explorer.DataFrame.mutate(max_datagouv_last_modified: max(datagouv_last_modified))
    |> Explorer.DataFrame.mutate(
      deduplication_status:
        cond do
          is_not_nil(deduplication_status) ->
            deduplication_status

          datagouv_last_modified == max_datagouv_last_modified ->
            "kept_because_resource_more_recent"

          true ->
            "removed_because_resource_not_more_recent"
        end
    )
    |> Explorer.DataFrame.discard("max_datagouv_last_modified")
  end
end
