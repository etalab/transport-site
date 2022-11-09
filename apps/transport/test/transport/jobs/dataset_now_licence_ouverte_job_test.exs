defmodule Transport.Test.Transport.Jobs.DatasetNowLicenceOuverteJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.DatasetNowLicenceOuverteJob

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "perform" do
    %{id: dataset_id} = insert(:dataset, is_active: true)

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             "foo@example.com" = _to,
                             "contact@transport.beta.gouv.fr",
                             "Jeu de données maintenant en licence ouverte" = _subject,
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
          reason: :dataset_now_licence_ouverte,
          extra_delays: []
        }
      ]
    end)

    assert :ok == perform_job(DatasetNowLicenceOuverteJob, %{"dataset_id" => dataset_id})
  end
end
