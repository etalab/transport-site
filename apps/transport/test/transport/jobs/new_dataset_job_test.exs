defmodule Transport.Test.Transport.Jobs.NewDatasetJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.NewDatasetJob

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "perform" do
    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr" = _subject,
                             "contact@transport.beta.gouv.fr",
                             "foo@example.com" = _to,
                             "contact@transport.beta.gouv.fr",
                             "Nouveau jeu de données référencé",
                             plain_text_body,
                             "" = _html_part ->
      assert plain_text_body =~ ~r/Bonjour/
      :ok
    end)

    Transport.Notifications.FetcherMock
    |> expect(:fetch_config!, fn ->
      [
        %Transport.Notifications.Item{
          dataset_slug: nil,
          emails: ["foo@example.com"],
          reason: :new_dataset,
          extra_delays: []
        }
      ]
    end)

    assert :ok == perform_job(NewDatasetJob, %{"dataset_id" => insert(:dataset).id})
  end
end
