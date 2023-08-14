defmodule Transport.Test.Transport.Jobs.DatasetsSwitchingClimateResilienceBillJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.DatasetsSwitchingClimateResilienceBillJob

  doctest DatasetsSwitchingClimateResilienceBillJob, import: true

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "datasets_custom_tags_changes, datasets_previously_climate_resilience_bill and datasets_now_climate_resilience_bill" do
    %{id: d1_id} = d1 = insert(:dataset)
    %{id: d2_id} = d2 = insert(:dataset)
    d3 = insert(:dataset)

    # d1 now has the `loi-climat-resilience` tag
    insert(:dataset_history,
      dataset: d1,
      inserted_at: ~U[2023-04-20 14:30:00.000Z],
      payload: %{"custom_tags" => ["loi-climat-resilience"]}
    )

    insert(:dataset_history,
      dataset: d1,
      inserted_at: ~U[2023-04-13 14:30:00.000Z],
      payload: %{"custom_tags" => ["foo"]}
    )

    # d2 had the `loi-climat-resilience` tag
    insert(:dataset_history,
      dataset: d2,
      inserted_at: ~U[2023-04-20 14:30:00.000Z],
      payload: %{"custom_tags" => ["foo"]}
    )

    insert(:dataset_history,
      dataset: d2,
      inserted_at: ~U[2023-04-13 14:30:00.000Z],
      payload: %{"custom_tags" => ["loi-climat-resilience"]}
    )

    # d3 kept the `loi-climat-resilience` tag
    insert(:dataset_history,
      dataset: d3,
      inserted_at: ~U[2023-04-20 14:30:00.000Z],
      payload: %{"custom_tags" => ["loi-climat-resilience"]}
    )

    insert(:dataset_history,
      dataset: d3,
      inserted_at: ~U[2023-04-13 14:30:00.000Z],
      payload: %{"custom_tags" => ["loi-climat-resilience"]}
    )

    assert [
             [
               %DB.DatasetHistory{dataset_id: ^d1_id, payload: %{"custom_tags" => ["loi-climat-resilience"]}},
               %DB.Dataset{id: ^d1_id},
               %DB.DatasetHistory{dataset_id: ^d1_id, payload: %{"custom_tags" => ["foo"]}}
             ],
             [
               %DB.DatasetHistory{dataset_id: ^d2_id, payload: %{"custom_tags" => ["foo"]}},
               %DB.Dataset{id: ^d2_id},
               %DB.DatasetHistory{dataset_id: ^d2_id, payload: %{"custom_tags" => ["loi-climat-resilience"]}}
             ]
           ] = changes = DatasetsSwitchingClimateResilienceBillJob.datasets_custom_tags_changes(~D[2023-04-20])

    assert [
             [
               %DB.DatasetHistory{dataset_id: ^d1_id, payload: %{"custom_tags" => ["loi-climat-resilience"]}},
               %DB.Dataset{id: ^d1_id},
               %DB.DatasetHistory{dataset_id: ^d1_id, payload: %{"custom_tags" => ["foo"]}}
             ]
           ] = DatasetsSwitchingClimateResilienceBillJob.datasets_now_climate_resilience_bill(changes)

    assert [
             [
               %DB.DatasetHistory{dataset_id: ^d2_id, payload: %{"custom_tags" => ["foo"]}},
               %DB.Dataset{id: ^d2_id},
               %DB.DatasetHistory{dataset_id: ^d2_id, payload: %{"custom_tags" => ["loi-climat-resilience"]}}
             ]
           ] = DatasetsSwitchingClimateResilienceBillJob.datasets_previously_climate_resilience_bill(changes)
  end

  test "perform" do
    %{id: d1_id} = d1 = insert(:dataset, type: "public-transit", custom_title: "FooBar")
    %{id: d2_id} = d2 = insert(:dataset, type: "public-transit", custom_title: "BarBaz")

    # d1 now has the `loi-climat-resilience` tag
    insert(:dataset_history,
      dataset: d1,
      inserted_at: ~U[2023-04-20 14:30:00.000Z],
      payload: %{"custom_tags" => ["loi-climat-resilience"]}
    )

    insert(:dataset_history,
      dataset: d1,
      inserted_at: ~U[2023-04-13 14:30:00.000Z],
      payload: %{"custom_tags" => ["foo"]}
    )

    # d2 had the `loi-climat-resilience` tag
    insert(:dataset_history,
      dataset: d2,
      inserted_at: ~U[2023-04-20 14:30:00.000Z],
      payload: %{"custom_tags" => ["foo"]}
    )

    insert(:dataset_history,
      dataset: d2,
      inserted_at: ~U[2023-04-13 14:30:00.000Z],
      payload: %{"custom_tags" => ["loi-climat-resilience"]}
    )

    %DB.Contact{id: contact_id, email: email} = insert_contact()

    insert(:notification_subscription, %{
      reason: :datasets_switching_climate_resilience_bill,
      source: :admin,
      role: :producer,
      contact_id: contact_id
    })

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             ^email,
                             "contact@transport.beta.gouv.fr",
                             "Loi climat et résilience : suivi des jeux de données" = _subject,
                             "" = _plain_text,
                             html ->
      assert html =~
               ~s(Les jeux de données suivants font désormais l’objet d’une intégration obligatoire :\n\n<a href="http://127.0.0.1:5100/datasets/#{d1.slug}">#{d1.custom_title}</a>)

      assert html =~
               ~s(Les jeux de données suivants faisaient l’objet d’une intégration obligatoire et ne font plus l’objet de cette obligation :\n\n<a href="http://127.0.0.1:5100/datasets/#{d2.slug}">#{d2.custom_title}</a>)

      :ok
    end)

    assert :ok == perform_job(DatasetsSwitchingClimateResilienceBillJob, %{}, inserted_at: ~U[2023-04-21 06:00:00.000Z])

    # Logs have been saved
    assert [
             %DB.Notification{email: ^email, reason: :datasets_switching_climate_resilience_bill, dataset_id: ^d1_id},
             %DB.Notification{email: ^email, reason: :datasets_switching_climate_resilience_bill, dataset_id: ^d2_id}
           ] = DB.Notification |> DB.Repo.all() |> Enum.sort_by(& &1.dataset_id)
  end
end
