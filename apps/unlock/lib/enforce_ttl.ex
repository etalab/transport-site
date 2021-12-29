defmodule Unlock.EnforceTTL do
  @moduledoc """
  A module running a method every 5s to make sure that all proxy keys have an appropriate TTL.

  If a cache key does not have a TTL or if its TTL
  is greater than the item's configuration,
  it is deleted.
  """
  use GenServer
  import Unlock.Shared

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  @impl true
  def init(state) do
    schedule_work()
    {:ok, state}
  end

  @impl true
  def handle_info(:work, state) do
    cache_keys() |> Enum.each(fn key -> enforce_ttl(key, cache_ttl(key)) end)
    schedule_work()
    {:noreply, state}
  end

  defp enforce_ttl(key, {:ok, ttl}) do
    ttl_over_config_value = is_integer(ttl) and ttl > ttl_config_value(key)

    if is_nil(ttl) or ttl_over_config_value do
      Sentry.capture_message("Removed #{key} from cache. ttl was #{ttl} while config is #{ttl_config_value(key)}")
      Cachex.del(cache_name(), key)
    end
  end

  defp ttl_config_value(cache_key) do
    (cache_key |> proxy_config()).ttl * 1000
  end

  defp proxy_config(cache_key) do
    config = Application.fetch_env!(:unlock, :config_fetcher).fetch_config!()

    Map.fetch!(config, String.replace_prefix(cache_key, cache_prefix(), ""))
  end

  defp schedule_work do
    Process.send_after(self(), :work, :timer.seconds(5))
  end
end
