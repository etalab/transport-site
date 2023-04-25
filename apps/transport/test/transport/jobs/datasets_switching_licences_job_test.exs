defmodule Transport.Test.Transport.Jobs.DatasetsSwitchingLicencesJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.DatasetsSwitchingLicencesJob

  doctest DatasetsSwitchingLicencesJob, import: true

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "datasets_licence_changes, datasets_previously_licence_ouverte and datasets_now_licence_ouverte" do
    %{id: d1_id} = d1 = insert(:dataset)
    %{id: d2_id} = d2 = insert(:dataset)
    d3 = insert(:dataset)

    # d1 is now `fr-lo`
    insert(:dataset_history, dataset: d1, inserted_at: ~U[2023-04-20 14:30:00.000Z], payload: %{"licence" => "fr-lo"})

    insert(:dataset_history, dataset: d1, inserted_at: ~U[2023-04-13 14:30:00.000Z], payload: %{"licence" => "odc-odbl"})

    # d2 was previously `fr-lo`
    insert(:dataset_history, dataset: d2, inserted_at: ~U[2023-04-20 14:30:00.000Z], payload: %{"licence" => "odc-odbl"})

    insert(:dataset_history, dataset: d2, inserted_at: ~U[2023-04-13 14:30:00.000Z], payload: %{"licence" => "fr-lo"})

    # d3 stayed `fr-lo`
    insert(:dataset_history, dataset: d3, inserted_at: ~U[2023-04-20 14:30:00.000Z], payload: %{"licence" => "fr-lo"})
    insert(:dataset_history, dataset: d3, inserted_at: ~U[2023-04-13 14:30:00.000Z], payload: %{"licence" => "fr-lo"})

    assert [
             [
               %DB.DatasetHistory{dataset_id: ^d1_id, payload: %{"licence" => "fr-lo"}},
               %DB.Dataset{id: ^d1_id},
               %DB.DatasetHistory{dataset_id: ^d1_id, payload: %{"licence" => "odc-odbl"}}
             ],
             [
               %DB.DatasetHistory{dataset_id: ^d2_id, payload: %{"licence" => "odc-odbl"}},
               %DB.Dataset{id: ^d2_id},
               %DB.DatasetHistory{dataset_id: ^d2_id, payload: %{"licence" => "fr-lo"}}
             ]
           ] = changes = DatasetsSwitchingLicencesJob.datasets_licence_changes(~D[2023-04-20])

    assert [
             [
               %DB.DatasetHistory{dataset_id: ^d1_id, payload: %{"licence" => "fr-lo"}},
               %DB.Dataset{id: ^d1_id},
               %DB.DatasetHistory{dataset_id: ^d1_id, payload: %{"licence" => "odc-odbl"}}
             ]
           ] = DatasetsSwitchingLicencesJob.datasets_now_licence_ouverte(changes)

    assert [
             [
               %DB.DatasetHistory{dataset_id: ^d2_id, payload: %{"licence" => "odc-odbl"}},
               %DB.Dataset{id: ^d2_id},
               %DB.DatasetHistory{dataset_id: ^d2_id, payload: %{"licence" => "fr-lo"}}
             ]
           ] = DatasetsSwitchingLicencesJob.datasets_previously_licence_ouverte(changes)
  end

  test "perform" do
    %{id: d1_id} = d1 = insert(:dataset, type: "public-transit", custom_title: "FooBar")
    %{id: d2_id} = d2 = insert(:dataset, type: "public-transit", custom_title: "BarBaz")

    # d1 is now `fr-lo`
    insert(:dataset_history, dataset: d1, inserted_at: ~U[2023-04-20 14:30:00.000Z], payload: %{"licence" => "fr-lo"})

    insert(:dataset_history, dataset: d1, inserted_at: ~U[2023-04-13 14:30:00.000Z], payload: %{"licence" => "odc-odbl"})

    # d2 was previously `fr-lo`
    insert(:dataset_history, dataset: d2, inserted_at: ~U[2023-04-20 14:30:00.000Z], payload: %{"licence" => "odc-odbl"})

    insert(:dataset_history, dataset: d2, inserted_at: ~U[2023-04-13 14:30:00.000Z], payload: %{"licence" => "fr-lo"})

    %DB.Contact{id: contact_id, email: email} = insert_contact()
    insert(:notification_subscription, %{reason: :datasets_switching_licences, source: :admin, contact_id: contact_id})

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             ^email,
                             "contact@transport.beta.gouv.fr",
                             "Suivi des jeux de données en licence ouverte" = _subject,
                             plain_text_body,
                             "" = _html_part ->
      assert plain_text_body =~ ~r/^Bonjour/

      assert plain_text_body =~
               "Les jeux de données suivants sont désormais publiés en licence ouverte :\n* #{d1.custom_title} - (Transport public collectif - horaires théoriques) - http://127.0.0.1:5100/datasets/#{d1.slug}"

      assert plain_text_body =~
               "Les jeux de données suivants étaient publiés en licence ouverte et ont changé de licence :\n* #{d2.custom_title} - (Transport public collectif - horaires théoriques) - http://127.0.0.1:5100/datasets/#{d2.slug}"

      :ok
    end)

    assert :ok == perform_job(DatasetsSwitchingLicencesJob, %{}, inserted_at: ~U[2023-04-21 06:00:00.000Z])

    # Logs have been saved
    assert [
             %DB.Notification{email: ^email, reason: :datasets_switching_licences, dataset_id: ^d1_id},
             %DB.Notification{email: ^email, reason: :datasets_switching_licences, dataset_id: ^d2_id}
           ] = DB.Notification |> DB.Repo.all() |> Enum.sort_by(& &1.dataset_id)
  end
end
