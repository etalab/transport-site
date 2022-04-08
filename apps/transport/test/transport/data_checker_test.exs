defmodule Transport.DataCheckerTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
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

      # TODO: add assertions on the email sending mock (adapting the code below)

      # logs = capture_log(fun)
      # assert String.contains?(logs, ~s("To":[{"Email":"foo@example.com"}]))

      # assert String.contains?(
      #          logs,
      #          ~s({"Messages":[{"From":{"Email":"contact@transport.beta.gouv.fr","Name":"transport.data.gouv.fr"},"HtmlPart":"","ReplyTo":{"Email":"contact@transport.beta.gouv.fr"},"Subject":"Jeu de données arrivant à expiration")
      #        )
    end

    test "with a matching extra delay" do
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

      fun = fn ->
        Transport.DataChecker.send_outdated_data_notifications({custom_delay, [dataset]}, true)
      end

      logs = capture_log(fun)
      assert String.contains?(logs, ~s("To":[{"Email":"foo@example.com"}]))
    end

    test "with a non-matching extra delay" do
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

      fun = fn ->
        Transport.DataChecker.send_outdated_data_notifications({42, [dataset]}, true)
      end

      assert capture_log(fun) == ""
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
