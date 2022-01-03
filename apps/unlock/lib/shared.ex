defmodule Unlock.Shared do
  @moduledoc """
  DRY helpers to access cache items (shared between Unlock and main app)
  """

  def default_cache_expiration_seconds, do: 60

  def cache_prefix, do: "resource:"
  def cache_key(resource_slug), do: "#{cache_prefix()}#{resource_slug}"
  def cache_name, do: Unlock.Cachex
  def cache_entry(cache_key), do: Cachex.get!(cache_name(), cache_key)
  def cache_ttl(cache_key), do: Cachex.ttl(cache_name(), cache_key)

  def cache_keys do
    {:ok, keys} = Cachex.keys(cache_name())
    keys |> Enum.filter(fn k -> String.starts_with?(k, cache_prefix()) end)
  end
end
