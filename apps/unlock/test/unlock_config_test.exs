defmodule UnlockGitHubConfigTest do
  #
  # NOTE: Here we use Mox in global setup, and disable async.
  # It would be nice to avoid that in the future.
  # See:
  # - https://github.com/whitfin/cachex/issues/250
  # - https://hexdocs.pm/mox/Mox.html#module-multi-process-collaboration
  #
  import Mox
  # async false to ensure mox global mode works here, because
  # cachex fetch apparently works in its own process, and mox expectations
  # are per-process (see notes above)
  # also, we're using cachex without a wrapper, and not overriding the cache
  # "name", so this is all global state here until I improve the situation.
  use ExUnit.Case, async: false
  setup :set_mox_from_context
  setup :verify_on_exit!

  def feeds_yaml_config do
    %{
      "feeds" => [
        %{
          "unique_slug" => "test-slug",
          "url" => "http://localhost/real-time"
        }
      ]
    }
    |> Ymlr.document!()
  end

  @config_cache_name Unlock.Cachex
  @config_cache_key "config:proxy"

  test "GitHub.fetch_config!" do
    Cachex.del!(@config_cache_name, @config_cache_key)

    # the config module is expected to reach out to GitHub (here with a fake url)
    Unlock.HTTP.Client.Mock
    |> expect(:get!, fn url, headers ->
      assert url == "https://localhost/some-github-url"
      assert headers == [{"Authorization", "token some-test-github-auth-token"}]

      %Unlock.HTTP.Response{
        status: 200,
        body: feeds_yaml_config(),
        headers: []
      }
    end)

    data = Unlock.Config.GitHub.fetch_config!()
    # No TTL since we want to keep the configuration always
    assert Cachex.ttl(@config_cache_name, @config_cache_key) == {:ok, nil}

    assert data == %{
             "test-slug" => %Unlock.Config.Item{
               identifier: "test-slug",
               ttl: 0,
               target_url: "http://localhost/real-time"
             }
           }

    assert Cachex.get!(@config_cache_name, @config_cache_key) == data

    # client must not call the data anymore
    Unlock.HTTP.Client.Mock
    |> expect(:get!, 0, fn _url, _headers -> nil end)

    # yet data must not change
    assert Unlock.Config.GitHub.fetch_config!() == data
  end
end
