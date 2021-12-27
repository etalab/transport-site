defmodule Unlock.Shared do
  @moduledoc """
  DRY helpers to access cache items (shared between Unlock and main app)
  """

  def cache_key(resource_slug), do: "resource:#{resource_slug}"
  def cache_name, do: Unlock.Cachex
  def cache_entry(cache_key), do: Cachex.get!(cache_name(), cache_key)
  def cache_ttl(cache_key), do: Cachex.ttl(cache_name(), cache_key)
end
