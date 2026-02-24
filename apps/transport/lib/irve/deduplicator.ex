defmodule Transport.IRVE.Deduplicator do
  @moduledoc """
  A module to deduplicate IRVE valid PDCs in the database, taking as an entry point
  the dataframe from the `Transport.IRVE.DatabaseExporter` module.
  """

  require Explorer.DataFrame

  # Lowest priority number = highest priority, 1 = main priority, 2 = second priority, etc.
  # Don’t put two datasets on the same priority level
  # Prioritary datasets must have only a single resource tagged at static IRVE schema
  @prioritary_datasets [
    # Gireve
    %{datagouv_dataset_id: "63dccb1307e9b2f213a5130c", priority: 1},
    # Eco-movement
    %{datagouv_dataset_id: "64060c2ac773dcf3fabbe5d2", priority: 2},
    # Qualicharge
    %{datagouv_dataset_id: "6818bce2d9af175f6e01a1b2", priority: 3}
  ]

  @doc """
  Main method of deduplication.
  Takes a dataframe of IRVE valid PDCs,
  returns the same dataframe with an additional column "deduplication_status" with information about the duplicates.
  Deduplication is done on the "id_pdc_itinerance" column.
  For each group of lines sharing the same "id_pdc_itinerance", only one entry should have a "kept_because_reason" status.
  (It’s nearly the case, but there are edge cases.)
  We group the dataframe by this column, and then can use Explorer "group aware" aggregation functions.
  There are multiple filters applied, once a filter has written a deduplication_status, this won’t be overwritten by next filters.
  How every filter works in detail:
  - Unique: if a pdc is unique, it’s written in the deduplication_status column.
  - In_prioritary_datasets: we check the min value of the priority for each group of duplicates.
      - If no entry in the duplicates group is in a prioritary dataset, no status is written for this filter.
      - Else, we keep the one corresponding to this min (kept_because_in_prioritary_dataset) and we mark as duplicates all the other ones.
  - Date_maj: we look at the max date_maj for each group of duplicates.
    - If there is only one most recent date_maj, we keep it and mark others as duplicates.
    - If there are multiple with the same max date_maj, then we cannot decide for these entries (no status written),
      but we mark the eventual older ones as duplicates.
  - Datagouv_last_modified: then for the last undecided entries (that are dups that have the same and max date_maj…),
    we mark as kept the one(s) with the most recent datagouv_last_modified, and the others as duplicates.

  Values of the additional column:
  - unique
  - kept_because_in_prioritary_dataset
  - removed_because_not_in_prioritary_dataset
  - kept_because_date_maj_more_recent
  - removed_because_date_maj_not_more_recent
  - kept_because_resource_more_recent
  - removed_because_resource_not_more_recent
  """
  def add_duplicates_column(%Explorer.DataFrame{} = df) do
    # TODO at one point: deal with non_concerné and such.
    df
    |> exact_duplicate_in_same_file_rule()
    |> Explorer.DataFrame.group_by("id_pdc_itinerance")
    |> remove_non_concerne_rule()
    |> unique_rule()
    |> in_prioritary_datasets_rule()
    |> date_maj_rule()
    |> datagouv_last_modified_rule()
  end

  def discard_duplicates(df) do
    df
    |> Explorer.DataFrame.filter(
      deduplication_status in [
        "kept_because_exact_duplicate_in_same_file",
        "unique",
        "kept_because_date_maj_more_recent",
        "kept_because_resource_more_recent",
        "kept_because_in_prioritary_dataset"
      ]
    )
  end

  defp exact_duplicate_in_same_file_rule(df) do
    df
    # This is grouping by all columns, thus grouping identical entries (with same file ids) together
    |> Explorer.DataFrame.group_by(fn _col -> true end)
    |> Explorer.DataFrame.mutate(count_dups: count(id_pdc_itinerance))
    |> Explorer.DataFrame.mutate(
      deduplication_status:
        cond do
          count_dups > 1 and row_index(id_pdc_itinerance) == 0 ->
            "kept_because_exact_duplicate_in_same_file"

          count_dups > 1 ->
            "removed_because_exact_duplicate_in_same_file"

          true ->
            nil
        end
    )
    |> Explorer.DataFrame.discard("count_dups")
    |> Explorer.DataFrame.ungroup()
  end

  defp remove_non_concerne_rule(df) do
    df
    |> Explorer.DataFrame.mutate(
      deduplication_status:
        cond do
          is_not_nil(deduplication_status) ->
            deduplication_status

          id_pdc_itinerance == "Non concerné" ->
            "removed_because_non_concerne"

          true ->
            nil
        end
    )
  end

  defp unique_rule(df) do
    df
    |> Explorer.DataFrame.mutate(similar_pdc_count: count(datagouv_resource_id))
    |> Explorer.DataFrame.mutate(
      deduplication_status:
        if(similar_pdc_count == 1 and is_nil(deduplication_status), do: "unique", else: deduplication_status)
    )
    |> Explorer.DataFrame.discard("similar_pdc_count")
  end

  defp in_prioritary_datasets_rule(df) do
    priority_df = Explorer.DataFrame.new(@prioritary_datasets)

    df
    |> Explorer.DataFrame.join(priority_df, how: :left, on: "datagouv_dataset_id")
    |> Explorer.DataFrame.mutate(min_priority: min(priority))
    |> Explorer.DataFrame.mutate(
      deduplication_status:
        cond do
          is_not_nil(deduplication_status) ->
            deduplication_status

          priority == min_priority and is_not_nil(min_priority) ->
            "kept_because_in_prioritary_dataset"

          is_not_nil(min_priority) ->
            "removed_because_not_in_prioritary_dataset"

          true ->
            nil
        end
    )
    |> Explorer.DataFrame.discard("priority")
    |> Explorer.DataFrame.discard("min_priority")
  end

  defp date_maj_rule(df) do
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

          is_max_date_maj and count_is_max_date_maj == 1 ->
            "kept_because_date_maj_more_recent"

          not is_max_date_maj ->
            "removed_because_date_maj_not_more_recent"

          true ->
            nil
        end
    )
    |> Explorer.DataFrame.discard("max_date_maj")
    |> Explorer.DataFrame.discard("count_is_max_date_maj")
  end

  defp datagouv_last_modified_rule(df) do
    # Please note the dataframe received here is still grouped both by id_pdc_itinerance and is_max_date_maj
    # from the date_maj_rule.
    # This is quite important because in the date_maj_rule, we may have "incomplete" groups:
    # some entries are already discarded (because older date_maj),
    # So we only want to compare the datagouv_last_modified of the entries that are still "in competition"
    # (that have is_max_date_maj true)
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
    |> Explorer.DataFrame.ungroup()
    |> Explorer.DataFrame.discard("is_max_date_maj")
  end
end
