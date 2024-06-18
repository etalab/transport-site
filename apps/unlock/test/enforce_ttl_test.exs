defmodule Unlock.EnforceTTLTest do
  use ExUnit.Case, async: false
  import Unlock.Shared

  import Mox
  setup :verify_on_exit!

  setup do
    Cachex.clear(cache_name())
    on_exit(fn -> Cachex.clear(cache_name()) end)
  end

  defp cache_put(key, ttl \\ nil), do: Cachex.put!(cache_name(), key, 42, ttl: ttl)

  test "removes keys without a ttl or with a ttl greather than the configuration" do
    ttl_config_value = 10

    setup_proxy_config(%{
      "no_ttl" => %Unlock.Config.Item.Generic.HTTP{
        identifier: "no_ttl",
        target_url: "https://example.com",
        ttl: ttl_config_value
      },
      "with_ttl" => %Unlock.Config.Item.Generic.HTTP{
        identifier: "with_ttl",
        target_url: "https://example.com",
        ttl: ttl_config_value
      }
    })

    assert ttl_config_value < Unlock.Shared.default_cache_expiration_seconds()

    # NOTE: this test would be better served with individual assertions + runs
    # but to get there needs a bit more work.

    # proxy cache keys should be empty
    assert [] == cache_keys()
    # a non-bogus proxy entry: its TTL will make it expire
    cache_put(cache_key("with_ttl"), :timer.seconds(5))
    # a bogus proxy entry: its TTL is not set, causing it to never expire.
    # these are the one which are dangerous (see `EnforceTTL` documentation)
    # and which we want to remove
    cache_put(cache_key("no_ttl"))
    # a non-proxy entry: we do not want to impact those
    cache_put("no_prefix")

    # initially, the list of proxy cache keys should include only 2 entries
    assert ["resource:with_ttl", "resource:no_ttl"] == cache_keys()

    # this is expected to remove bogus entries (the ones without a TTL),
    # which would otherwise remain "available but stale" forever
    Unlock.EnforceTTL.handle_info(:work, %{})

    # explicitely written, the bogus key should not be there anymore
    refute "resource:no_ttl" in cache_keys()
    # a bit redundant, but exactly the non-bogus keys should be there
    assert ["resource:with_ttl"] == cache_keys()

    # non-proxy keys should still be there too
    assert "no_prefix" in Cachex.keys!(cache_name())
  end

  test "supports aggregate sub-keys" do
    ttl_config_value = 10
    slug = "some-slug"

    setup_proxy_config(%{
      "aggregate" => %Unlock.Config.Item.Aggregate{
        identifier: slug,
        ttl: 10,
        feeds: [
          %Unlock.Config.Item.Generic.HTTP{
            identifier: "first-remote",
            target_url: "http://localhost:1234",
            ttl: 10
          },
          %Unlock.Config.Item.Generic.HTTP{
            identifier: "second-remote",
            target_url: "http://localhost:1234",
            ttl: 10
          }
        ]
      }
    })

    assert ttl_config_value < Unlock.Shared.default_cache_expiration_seconds()

    # create a cache entry without cachex TTL to reproduce the bug
    # this case uses composite keys (for aggregate support)
    cache_put(cache_key("aggregate:first-remote"), nil)
    # create a non-bogus entry with proper Cachex TTL
    cache_put(cache_key("aggregate:second-remote"), :timer.seconds(5))

    assert ["resource:aggregate:first-remote", "resource:aggregate:second-remote"] == cache_keys()
    Unlock.EnforceTTL.handle_info(:work, %{})

    # bogus cache key should have been removed
    refute "resource:aggregate:first-remote" in cache_keys()
    # the other one should remain
    assert ["resource:aggregate:second-remote"] == cache_keys()
  end

  def setup_proxy_config(config) do
    Unlock.Config.Fetcher.Mock
    |> stub(:fetch_config!, fn -> config end)
  end
end
