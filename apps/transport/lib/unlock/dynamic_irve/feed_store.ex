defmodule Unlock.DynamicIRVE.FeedStore do
  @moduledoc """
  ETS-backed store for dynamic IRVE data. Two kinds of entries share one table:

    * per-feed snapshots, written by each `FeedWorker` on every tick
      (keyed internally by `{:feed, parent_id, slug}`)
    * per-aggregator snapshots, written by each `Aggregator` on every tick
      (keyed internally by `{:aggregate, parent_id}`)

  Callers should go through the typed helpers (`put_feed/3`, `get_aggregate/1`, ...)
  rather than constructing keys directly — the tuple shape is an implementation detail.
  """

  @table __MODULE__

  def create_table do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
  end

  def put_feed(parent_id, slug, data), do: put({:feed, parent_id, slug}, data)
  def get_feed(parent_id, slug), do: get({:feed, parent_id, slug})

  def put_aggregate(parent_id, data), do: put({:aggregate, parent_id}, data)
  def get_aggregate(parent_id), do: get({:aggregate, parent_id})

  defp put(key, data), do: :ets.insert(@table, {key, data})

  defp get(key) do
    case :ets.lookup(@table, key) do
      [{^key, data}] -> data
      [] -> nil
    end
  end
end
