defmodule Transport.NotificationsTest do
  use ExUnit.Case, async: false

  alias Transport.Notifications
  alias Transport.Notifications.{Fetcher, GitHub, Item}
  import Mox

  setup :set_mox_from_context
  setup :verify_on_exit!

  @config_cache_key "config:notifications"

  def parse_config(yaml), do: Fetcher.convert_yaml_to_config_items(yaml)
  def config_cache_name, do: GitHub.cache_name()

  test "parses and converts basic configuration" do
    yaml_config = """
    expiration:
      my_slug:
        emails:
          - foo@bar.com
          - foo@bar.fr
      other:
        emails:
          - foo@example.com
    """

    expected = [
      %Item{reason: :expiration, dataset_slug: "my_slug", emails: ["foo@bar.com", "foo@bar.fr"]},
      %Item{reason: :expiration, dataset_slug: "other", emails: ["foo@example.com"]}
    ]

    assert expected == parse_config(yaml_config)
  end

  test "can filter configuration" do
    config = [
      %Item{reason: :expiration, dataset_slug: "my_slug", emails: ["foo@bar.com", "foo@bar.fr"]},
      %Item{reason: :expiration, dataset_slug: "other", emails: ["foo@example.com"]}
    ]

    assert ["foo@bar.com", "foo@bar.fr"] ==
             Notifications.emails_for_reason(config, :expiration, %DB.Dataset{slug: "my_slug"})

    assert_raise ArgumentError, ~r/^nope is not a valid reason$/, fn ->
      Notifications.emails_for_reason(config, :nope, %DB.Dataset{slug: "my_slug"})
    end

    assert is_nil(Notifications.emails_for_reason(config, :expiration, %DB.Dataset{slug: "nope"}))
  end

  test "GitHub.fetch_config!" do
    setup_response()
    Cachex.del!(config_cache_name(), @config_cache_key)

    data = GitHub.fetch_config!()
    # No TTL since we want to keep the configuration always
    assert Cachex.ttl(config_cache_name(), @config_cache_key) == {:ok, nil}

    expected = [
      %Item{dataset_slug: "my_slug", emails: ["foo@bar.com", "foo@bar.fr"], reason: :expiration}
    ]

    assert expected == data
    assert Cachex.get!(config_cache_name(), @config_cache_key) == data
    assert GitHub.fetch_config!() == data
  end

  defp setup_response do
    Transport.HTTPoison.Mock
    |> expect(:get, 1, fn url, headers ->
      assert [{"Authorization", "token "}] == headers
      assert url == Application.fetch_env!(:transport, :notifications_github_config_url)

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: """
         expiration:
           my_slug:
             emails:
               - foo@bar.com
               - foo@bar.fr
         """,
         headers: [{"Content-Type", "text/yaml"}]
       }}
    end)
  end
end
