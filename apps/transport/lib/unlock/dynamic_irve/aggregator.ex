defmodule Unlock.DynamicIRVE.Aggregator do
  @moduledoc """
  Periodically concatenates the DataFrames of all feeds belonging to a
  single `DynamicIRVEAggregate` config item, adding an "origin" column
  (the slug). Stores the result in FeedStore (see `FeedStore.put_aggregate/2`)
  for the controller to serve.

  One Aggregator runs per config item.
  """
  use GenServer
  require Logger

  def start_link(%Unlock.Config.Item.DynamicIRVEAggregate{} = item) do
    GenServer.start_link(__MODULE__, item, name: via(item.identifier))
  end

  defp via(parent_id), do: {:via, Registry, {Unlock.DynamicIRVE.Registry, {:aggregator, parent_id}}}

  @impl true
  def init(item) do
    schedule_tick()
    {:ok, item}
  end

  @impl true
  def handle_info(:tick, item) do
    schedule_tick()
    aggregate(item)
    {:noreply, item}
  end

  defp aggregate(item) do
    dfs = collect_feed_dfs(item)

    if dfs == [] do
      Logger.warning("[DynamicIRVE:Aggregator:#{item.identifier}] No feeds available yet")
    else
      {microseconds, merged} = :timer.tc(fn -> Explorer.DataFrame.concat_rows(dfs) end)

      Logger.info(
        "[DynamicIRVE:Aggregator:#{item.identifier}] #{Explorer.DataFrame.n_rows(merged)} rows, concatenated in #{div(microseconds, 1000)}ms"
      )

      Unlock.DynamicIRVE.FeedStore.put_aggregate(
        item.identifier,
        %{df: merged, last_updated_at: DateTime.utc_now()}
      )
    end
  end

  defp collect_feed_dfs(item) do
    item.feeds
    |> Enum.map(fn feed -> {feed.slug, Unlock.DynamicIRVE.FeedStore.get_feed(item.identifier, feed.slug)} end)
    |> Enum.filter(fn {_, entry} -> match?(%{df: %Explorer.DataFrame{}}, entry) end)
    |> Enum.map(fn {slug, %{df: df}} ->
      Explorer.DataFrame.put(df, "origin", List.duplicate(slug, Explorer.DataFrame.n_rows(df)))
    end)
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, :timer.seconds(10))
  end
end
