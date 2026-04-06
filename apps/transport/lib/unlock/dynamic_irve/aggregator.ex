defmodule Unlock.DynamicIRVE.Aggregator do
  @moduledoc """
  Periodically concatenates all feed DataFrames into a single one,
  adding an "origin" column (the slug). Stores the result in FeedStore
  under the :aggregate key for the controller to serve.

  LIMITATION: only supports a single `dynamic-irve-aggregate` item in the
  global config. All running feed workers are merged into one aggregate,
  regardless of which config item they belong to.
  """
  use GenServer
  require Logger

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    schedule_tick()
    {:ok, nil}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule_tick()
    aggregate()
    {:noreply, state}
  end

  defp aggregate do
    dfs = collect_feed_dfs()

    if dfs == [] do
      Logger.warning("[DynamicIRVE:Aggregator] No feeds available yet")
    else
      {microseconds, merged} = :timer.tc(fn -> Explorer.DataFrame.concat_rows(dfs) end)
      Logger.info("[DynamicIRVE:Aggregator] #{Explorer.DataFrame.n_rows(merged)} rows, concatenated in #{div(microseconds, 1000)}ms")
      Unlock.DynamicIRVE.FeedStore.put(:aggregate, %{df: merged, last_updated_at: DateTime.utc_now()})
    end
  end

  defp running_slugs do
    DynamicSupervisor.which_children(Unlock.DynamicIRVE.FeedSupervisor)
    |> Enum.map(fn {_, pid, _, _} -> Unlock.DynamicIRVE.FeedWorker.slug(pid) end)
  end

  defp collect_feed_dfs do
    running_slugs()
    |> Enum.map(fn slug -> {slug, Unlock.DynamicIRVE.FeedStore.get(slug)} end)
    |> Enum.filter(fn {_, entry} -> match?(%{df: %Explorer.DataFrame{}}, entry) end)
    |> Enum.map(fn {slug, %{df: df}} ->
      Explorer.DataFrame.put(df, "origin", List.duplicate(slug, Explorer.DataFrame.n_rows(df)))
    end)
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, :timer.seconds(10))
  end
end
