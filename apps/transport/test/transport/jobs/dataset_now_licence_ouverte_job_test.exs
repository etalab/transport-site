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
    %DB.Contact{id: contact_id, email: email} = insert_contact()
    insert(:notification_subscription, %{reason: :dataset_now_licence_ouverte, source: :admin, contact_id: contact_id})

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             ^email,
                             "contact@transport.beta.gouv.fr",
                             "Jeu de données maintenant en licence ouverte" = _subject,
                             plain_text_body,
                             "" = _html_part ->
      assert plain_text_body =~ ~r/Bonjour/
      :ok
    end)

    assert :ok == perform_job(DatasetNowLicenceOuverteJob, %{"dataset_id" => dataset_id})

    # Logs have been saved
    assert [%DB.Notification{email: ^email, reason: :dataset_now_licence_ouverte, dataset_id: ^dataset_id}] =
             DB.Notification |> DB.Repo.all()
  end
end
