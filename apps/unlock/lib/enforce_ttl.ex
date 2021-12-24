defmodule Unlock.EnforceTTL do
  @moduledoc """
  A module running a method every 5s to make sure that all proxy keys have a TTL set.

  If a cache key does not have a TTL, it is deleted.
  """
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    schedule_work()
    {:ok, state}
  end

  def handle_info(:work, state) do
    Unlock.Shared.cache_keys() |> Enum.each(fn key -> enforce_ttl(key, Unlock.Shared.cache_ttl(key)) end)
    schedule_work()
    {:noreply, state}
  end

  defp enforce_ttl(key, {:ok, nil}), do: Cachex.del(Unlock.Shared.cache_name(), key)

  defp enforce_ttl(_key, _res), do: nil

  defp schedule_work do
    Process.send_after(self(), :work, 5 * 1000)
  end
end
