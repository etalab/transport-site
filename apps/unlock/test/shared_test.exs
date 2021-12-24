defmodule Unlock.SharedTest do
  use ExUnit.Case, async: false
  import Unlock.Shared

  setup do
    Cachex.clear(cache_name())
    on_exit(fn -> Cachex.clear(cache_name()) end)
  end

  defp cache_put(key, ttl \\ nil), do: Cachex.put!(cache_name(), key, 42, ttl: ttl)

  test "cache_key" do
    assert "resource:foo" == cache_key("foo")
  end

  test "cache_entry" do
    cache_put(cache_key("foo"))
    assert 42 == cache_entry(cache_key("foo"))
    assert nil == cache_entry(cache_key("bar"))
  end

  test "cache_ttl" do
    cache_put(cache_key("foo"), :timer.seconds(5))
    cache_put(cache_key("baz"))
    {:ok, ttl} = cache_ttl(cache_key("foo"))
    assert_in_delta ttl / 1000.0, 5, 1
    assert {:ok, nil} == cache_ttl(cache_key("bar"))
    assert {:ok, nil} == cache_ttl(cache_key("baz"))
  end

  test "cache_keys" do
    assert [] == cache_keys()
    cache_put(cache_key("with_ttl"), :timer.seconds(5))
    cache_put(cache_key("no_ttl"))
    cache_put("no_prefix")

    assert ["resource:with_ttl", "resource:no_ttl"] == cache_keys()
  end
end
