defmodule Unlock.DynamicIRVE.FeedStore do
  @moduledoc """
  ETS-backed store for dynamic IRVE feed data.
  Workers write here after each fetch. Readers (controller, debug)
  read directly — no GenServer.call needed, no coupling with workers.
  """

  @table __MODULE__

  def create_table do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
  end

  def put(slug, data) do
    :ets.insert(@table, {slug, data})
  end

  def get(slug) do
    case :ets.lookup(@table, slug) do
      [{^slug, data}] -> data
      [] -> nil
    end
  end
end
