defmodule Unlock.EnforceTTLTest do
  use ExUnit.Case, async: false
  import Unlock.Shared

  setup do
    Cachex.clear(cache_name())
    on_exit(fn -> Cachex.clear(cache_name()) end)
  end

  defp cache_put(key, ttl \\ nil), do: Cachex.put!(cache_name(), key, 42, ttl: ttl)

  test "removes keys without a ttl" do
    assert [] == cache_keys()
    cache_put(cache_key("with_ttl"), :timer.seconds(5))
    cache_put(cache_key("no_ttl"))
    cache_put("no_prefix")

    assert ["resource:with_ttl", "resource:no_ttl"] == cache_keys()

    Unlock.EnforceTTL.handle_info(:work, %{})

    assert ["resource:with_ttl"] == cache_keys()
    assert ["resource:with_ttl", "no_prefix"] == Cachex.keys!(cache_name())
  end
end
