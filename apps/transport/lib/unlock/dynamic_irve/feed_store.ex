defmodule Unlock.DynamicIRVE.FeedStore do
  @moduledoc """
  ETS-backed cache of per-feed DataFrame snapshots.

  Workers (`FeedWorker`) write on every tick; readers (controller, status)
  read directly — no GenServer.call needed.
  """

  @table __MODULE__

  def create_table do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
  end

  def put_feed(parent_id, slug, data), do: :ets.insert(@table, {{parent_id, slug}, data})

  def get_feed(parent_id, slug) do
    case :ets.lookup(@table, {parent_id, slug}) do
      [{_, data}] -> data
      [] -> nil
    end
  end
end
