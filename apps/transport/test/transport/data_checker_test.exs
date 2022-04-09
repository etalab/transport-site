defmodule Transport.DataCheckerTest do
  use ExUnit.Case, async: true
  import Mox
  import DB.Factory

  setup :verify_on_exit!

  test "link_and_name relies on proper email host name" do
    dataset = build(:dataset)
    link = Transport.DataChecker.link(dataset)
    assert URI.parse(link).host == "email.localhost"
  end

  describe "send_outdated_data_notifications" do
    test "with a default delay" do
      Transport.EmailSender.Mock
      |> expect(:send_mail, fn "transport.data.gouv.fr" = _subject,
                               "contact@transport.beta.gouv.fr",
                               "foo@example.com" = _to,
                               "contact@transport.beta.gouv.fr",
                               "Jeu de données arrivant à expiration",
                               plain_text_body,
                               "" = _html_part ->
        assert plain_text_body =~ ~r/Bonjour/
        :ok
      end)

      dataset_slug = "slug"

      Transport.Notifications.FetcherMock
      |> expect(:fetch_config!, fn ->
        [
          %Transport.Notifications.Item{
            dataset_slug: dataset_slug,
            emails: ["foo@example.com"],
            reason: :expiration,
            extra_delays: []
          }
        ]
      end)

      dataset = %DB.Dataset{slug: dataset_slug, datagouv_title: "title"}

      Transport.DataChecker.send_outdated_data_notifications({7, [dataset]})

      verify!(Transport.EmailSender.Mock)
    end

    test "with a matching extra delay" do
      Transport.EmailSender.Mock
      |> expect(:send_mail, fn _, _, "foo@example.com" = _to, _, _, _, _ -> :ok end)

      dataset_slug = "slug"
      custom_delay = 30

      Transport.Notifications.FetcherMock
      |> expect(:fetch_config!, fn ->
        [
          %Transport.Notifications.Item{
            dataset_slug: dataset_slug,
            emails: ["foo@example.com"],
            reason: :expiration,
            extra_delays: [custom_delay]
          }
        ]
      end)

      dataset = %DB.Dataset{slug: dataset_slug, datagouv_title: "title"}

      Transport.DataChecker.send_outdated_data_notifications({custom_delay, [dataset]})
    end

    test "with a non-matching extra delay" do
      Transport.EmailSender.Mock
      |> expect(:send_mail, 0, fn _, _, _, _, _, _, _ -> :ok end)

      dataset_slug = "slug"

      Transport.Notifications.FetcherMock
      |> expect(:fetch_config!, fn ->
        [
          %Transport.Notifications.Item{
            dataset_slug: dataset_slug,
            emails: ["foo@example.com"],
            reason: :expiration,
            extra_delays: [30]
          }
        ]
      end)

      dataset = %DB.Dataset{slug: dataset_slug, datagouv_title: "title"}

      Transport.DataChecker.send_outdated_data_notifications({42, [dataset]})
    end
  end

  test "possible_delays" do
    Transport.Notifications.FetcherMock
    |> expect(:fetch_config!, fn ->
      [
        %Transport.Notifications.Item{
          dataset_slug: "slug",
          emails: ["foo@example.com"],
          reason: :expiration,
          extra_delays: [14, 30]
        },
        %Transport.Notifications.Item{
          dataset_slug: "other",
          emails: ["foo@example.com"],
          reason: :expiration,
          extra_delays: [30, 42]
        }
      ]
    end)

    assert [0, 7, 14, 30, 42] == Transport.DataChecker.possible_delays()
  end
end
