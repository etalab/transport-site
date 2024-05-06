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

    assert [] == cache_keys()
    cache_put(cache_key("with_ttl"), :timer.seconds(5))
    cache_put(cache_key("no_ttl"))
    cache_put("no_prefix")

    assert ["resource:with_ttl", "resource:no_ttl"] == cache_keys()

    Unlock.EnforceTTL.handle_info(:work, %{})

    assert ["resource:with_ttl"] == cache_keys()
    assert ["resource:with_ttl", "no_prefix"] == Cachex.keys!(cache_name())
  end

  test "supports aggregate sub-keys" do
    ttl_config_value = 10
    slug = "some-slug"

    setup_proxy_config(%{
      "no_ttl" => %Unlock.Config.Item.Aggregate{
        identifier: slug,
        ttl: 10,
        feeds: [
          %Unlock.Config.Item.Generic.HTTP{
            identifier: "first-remote",
            target_url: "http://localhost:1234",
            ttl: 10
          }
        ]
      }
    })

    assert ttl_config_value < Unlock.Shared.default_cache_expiration_seconds()

    assert [] == cache_keys()
    # this uses composite keys
    cache_put(cache_key("no_ttl:first-remote"))

    assert ["resource:no_ttl:first-remote"] == cache_keys()

    Unlock.EnforceTTL.handle_info(:work, %{})

    # TODO: add a couple of extra assertions here
  end

  def setup_proxy_config(config) do
    Unlock.Config.Fetcher.Mock
    |> stub(:fetch_config!, fn -> config end)
  end
end
