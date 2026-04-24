defmodule Unlock.DynamicIRVE.Renderer do
  @moduledoc """
  Builds and renders the aggregated dynamic IRVE DataFrame.

  `aggregate/1` concatenates the latest per-feed snapshots from
  `Unlock.DynamicIRVE.FeedStore`, tagging each row with its source slug.
  `render/3` serializes the result as CSV or Parquet, with optional
  per-source row cap and origin column projection.
  """

  alias Explorer.DataFrame
  alias Unlock.DynamicIRVE.FeedStore

  def aggregate(item) do
    item.feeds
    |> Enum.flat_map(&tagged_df(item.identifier, &1))
    |> concat()
  end

  def render(df, format, opts) do
    df
    |> apply_limit(Keyword.get(opts, :limit_per_source))
    |> DataFrame.select(columns(Keyword.get(opts, :include_origin, false)))
    |> dump(format)
  end

  defp tagged_df(parent_id, feed) do
    case FeedStore.get_feed(parent_id, feed.slug) do
      %{df: %DataFrame{} = df} ->
        [DataFrame.put(df, "origin", List.duplicate(feed.slug, DataFrame.n_rows(df)))]

      _ ->
        []
    end
  end

  defp concat([]), do: nil
  defp concat(dfs), do: DataFrame.concat_rows(dfs)

  defp apply_limit(df, nil), do: df

  defp apply_limit(df, n) when is_integer(n),
    do: df |> DataFrame.group_by("origin") |> DataFrame.head(n) |> DataFrame.ungroup()

  defp columns(false), do: Transport.IRVE.DynamicIRVESchema.build_schema_fields_list()
  defp columns(true), do: columns(false) ++ ["origin"]

  defp dump(df, :csv), do: {DataFrame.dump_csv!(df), "text/csv", "csv"}
  defp dump(df, :parquet), do: {DataFrame.dump_parquet!(df), "application/vnd.apache.parquet", "parquet"}
end
