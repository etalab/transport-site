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
    new_dataset:
      - bar@baz.com
      - foo@baz.com
    dataset_now_licence_ouverte:
      - bar@foo.com
    expiration:
      my_slug:
        emails:
          - foo@bar.com
          - foo@bar.fr
      other:
        emails:
          - foo@example.com
        extra_delays: [30]
    """

    expected = [
      %Item{reason: :expiration, dataset_slug: "my_slug", emails: ["foo@bar.com", "foo@bar.fr"], extra_delays: []},
      %Item{reason: :expiration, dataset_slug: "other", emails: ["foo@example.com"], extra_delays: [30]},
      %Item{reason: :new_dataset, dataset_slug: nil, emails: ["bar@baz.com", "foo@baz.com"], extra_delays: nil},
      %Item{reason: :dataset_now_licence_ouverte, dataset_slug: nil, emails: ["bar@foo.com"], extra_delays: nil}
    ]

    assert expected == parse_config(yaml_config)
  end

  test "can filter configuration" do
    config = [
      %Item{reason: :expiration, dataset_slug: "my_slug", emails: ["foo@bar.com", "foo@bar.fr"], extra_delays: []},
      %Item{reason: :expiration, dataset_slug: "other", emails: ["foo@example.com"], extra_delays: []},
      %Item{reason: :new_dataset, dataset_slug: nil, emails: ["foo@baz.com", "nope@baz.com"], extra_delays: nil},
      %Item{reason: :dataset_now_licence_ouverte, dataset_slug: nil, emails: ["bar@foo.com"], extra_delays: nil}
    ]

    assert ["foo@bar.com", "foo@bar.fr"] ==
             Notifications.emails_for_reason(config, :expiration, %DB.Dataset{slug: "my_slug"})

    # :dataset_with_error and :resource_unavailable are an alias for :expiration, for now
    ~w(dataset_with_error resource_unavailable)a
    |> Enum.each(fn reason ->
      assert Notifications.emails_for_reason(config, :expiration, %DB.Dataset{slug: "my_slug"}) ==
               Notifications.emails_for_reason(config, reason, %DB.Dataset{slug: "my_slug"})
    end)

    # Raises for an unknown reason
    assert_raise FunctionClauseError, fn ->
      Notifications.emails_for_reason(config, :nope, %DB.Dataset{slug: "my_slug"})
    end

    # Returns an empty list for valid reason but if the dataset isn't in the config
    ~w(expiration dataset_with_error resource_unavailable)a
    |> Enum.each(fn reason ->
      assert [] == Notifications.emails_for_reason(config, reason, %DB.Dataset{slug: "nope"})
    end)

    assert ["foo@baz.com", "nope@baz.com"] == Notifications.emails_for_reason(config, :new_dataset)
    assert ["bar@foo.com"] == Notifications.emails_for_reason(config, :dataset_now_licence_ouverte)
  end

  test "is_valid_extra_delay?" do
    config = [
      %Item{reason: :expiration, dataset_slug: "my_slug", emails: ["foo@bar.com", "foo@bar.fr"], extra_delays: []},
      %Item{reason: :expiration, dataset_slug: "other", emails: ["foo@example.com"], extra_delays: [30]}
    ]

    assert Notifications.is_valid_extra_delay?(config, :expiration, %DB.Dataset{slug: "other"}, 30)
    refute Notifications.is_valid_extra_delay?(config, :expiration, %DB.Dataset{slug: "other"}, 42)
    refute Notifications.is_valid_extra_delay?(config, :expiration, %DB.Dataset{slug: "my_slug"}, 14)
    refute Notifications.is_valid_extra_delay?(config, :expiration, %DB.Dataset{slug: "nope"}, 14)
  end

  test "GitHub.fetch_config!" do
    setup_response()
    Cachex.del!(config_cache_name(), @config_cache_key)

    data = GitHub.fetch_config!()
    # No TTL since we want to keep the configuration always
    assert Cachex.ttl(config_cache_name(), @config_cache_key) == {:ok, nil}

    expected = [
      %Item{dataset_slug: "my_slug", emails: ["foo@bar.com", "foo@bar.fr"], reason: :expiration, extra_delays: []},
      %Item{reason: :new_dataset, dataset_slug: nil, emails: ["foo@baz.com", "nope@baz.com"], extra_delays: nil},
      %Item{reason: :dataset_now_licence_ouverte, dataset_slug: nil, emails: ["bar@foo.com"], extra_delays: nil}
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
         new_dataset:
          - foo@baz.com
          - nope@baz.com
         dataset_now_licence_ouverte:
          - bar@foo.com
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
