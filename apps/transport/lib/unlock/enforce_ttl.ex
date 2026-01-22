defmodule Unlock.EnforceTTL do
  @moduledoc """
  A module running a method every 5s to make sure that all proxy keys have an appropriate TTL.

  If a cache key does not have a TTL or if its TTL
  is greater than the item's configuration,
  it is deleted.

  This module is a work-around for an issue we faced with Cachex, see:
  - https://github.com/etalab/transport-site/issues/2028
  - https://github.com/etalab/transport-site/pull/2961
  - https://github.com/whitfin/cachex/issues/304

  At time of writing, it is believed that the issue still occur in rare occasions:
  - https://github.com/etalab/transport-site/issues/2976
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
    cache_keys()
    # For S3 items we store another key ending with `:etag` without a TTL
    |> Enum.reject(&String.ends_with?(&1, ":etag"))
    |> Enum.each(fn key -> enforce_ttl(key, cache_ttl(key)) end)

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

  # Figure out which proxy config item corresponds to a given cache key
  defp proxy_config(cache_key) do
    config = Application.fetch_env!(:transport, :unlock_config_fetcher).fetch_config!()

    parts =
      cache_key
      |> String.replace_prefix(cache_prefix(), "")
      |> String.split(Unlock.Shared.cache_separator())

    proxy_config_item(config, parts)
  end

  # "regular" items (`resource:identifier`)
  def proxy_config_item(config, [identifier]) do
    Map.fetch!(config, identifier)
  end

  # "aggregate" sub-items (`resource:identifier:sub_identifier`)
  # "gbfs" sub feeds (`resource:identifier:gbfs.json`)
  def proxy_config_item(config, [identifier, sub_identifier]) do
    case Map.get(config, identifier) do
      %Unlock.Config.Item.Aggregate{} ->
        config
        |> Map.fetch!(identifier)
        |> Map.fetch!(:feeds)
        |> Enum.filter(&(&1.identifier == sub_identifier))
        |> hd()

      %Unlock.Config.Item.GBFS{} ->
        config |> Map.fetch!(identifier)
    end
  end

  defp schedule_work do
    Process.send_after(self(), :work, :timer.seconds(5))
  end
end
