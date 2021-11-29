defmodule Transport.DataCheckerTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  import Mox

  test "send_outdated_data_notifications" do
    dataset_slug = "slug"

    Transport.Notifications.FetcherMock
    |> expect(:fetch_config!, fn ->
      [
        %Transport.Notifications.Item{
          dataset_slug: dataset_slug,
          emails: ["foo@example.com"],
          reason: :expiration
        }
      ]
    end)

    dataset = %DB.Dataset{slug: dataset_slug, title: "title"}

    fun = fn ->
      Transport.DataChecker.send_outdated_data_notifications({1, [dataset]}, true)
    end

    logs = capture_log(fun)
    assert String.contains?(logs, ~s("To":[{"Email":"foo@example.com"}]))

    assert String.contains?(
             logs,
             ~s({"Messages":[{"From":{"Email":"contact@transport.beta.gouv.fr","Name":"transport.data.gouv.fr"},"HtmlPart":"","ReplyTo":{"Email":"contact@transport.beta.gouv.fr"},"Subject":"Jeu de données arrivant à expiration")
           )
  end
end
