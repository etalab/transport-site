defmodule Unlock.DynamicIRVE.Status do
  @moduledoc """
  Builds the JSON-ready status payload for a `DynamicIRVEAggregate` item:
  per-feed state (OK/KO/pending) + row counts, and total row count of the
  latest aggregate.
  """

  alias Unlock.DynamicIRVE.FeedStore

  def build(%Unlock.Config.Item.DynamicIRVEAggregate{} = item) do
    %{
      feeds: Enum.map(item.feeds, &feed_entry(item.identifier, &1)),
      row_count: item.identifier |> FeedStore.get_aggregate() |> row_count()
    }
  end

  defp feed_entry(parent_id, feed) do
    data = FeedStore.get_feed(parent_id, feed.slug)
    data |> feed_status(feed.slug) |> Map.put(:row_count, row_count(data))
  end

  defp feed_status(nil, slug), do: %{slug: slug, status: "pending"}

  defp feed_status(%{error: nil, last_updated_at: last_updated_at}, slug),
    do: %{slug: slug, status: "OK", last_updated_at: last_updated_at}

  defp feed_status(%{error: error, last_errored_at: last_errored_at, last_updated_at: last_updated_at}, slug),
    do: %{slug: slug, status: "KO", error: error, last_errored_at: last_errored_at, last_updated_at: last_updated_at}

  defp row_count(%{df: %Explorer.DataFrame{} = df}), do: Explorer.DataFrame.n_rows(df)
  defp row_count(_), do: 0
end
