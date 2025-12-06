defmodule Unlock.Shared do
  @moduledoc """
  DRY helpers to access cache items (shared between Unlock and main app)
  """

  def default_cache_expiration_seconds, do: 60

  def cache_name, do: Unlock.Cachex
  def cache_prefix, do: "resource@"
  def metric_cache_prefix, do: "metric@"
  def cache_separator, do: "@"

  def cache_key(resource_slug), do: "#{cache_prefix()}#{resource_slug}"

  def cache_key(resource_slug, sub_item_identifier),
    do: "#{cache_key(resource_slug)}#{cache_separator()}#{sub_item_identifier}"

  def metric_cache_key(%{target: target, event: event}) do
    Enum.join([metric_cache_prefix(), event, target], cache_separator())
  end

  def cache_entry(cache_key), do: Cachex.get!(cache_name(), cache_key)
  def cache_ttl(cache_key), do: Cachex.ttl(cache_name(), cache_key)

  def cache_keys do
    {:ok, keys} = Cachex.keys(cache_name())
    starts_with_prefix(keys, cache_prefix())
  end

  def metric_cache_keys do
    {:ok, keys} = Cachex.keys(cache_name())
    starts_with_prefix(keys, metric_cache_prefix())
  end

  defp starts_with_prefix(keys, prefix) do
    Enum.filter(keys, fn k -> String.starts_with?(k, prefix) end)
  end
end
