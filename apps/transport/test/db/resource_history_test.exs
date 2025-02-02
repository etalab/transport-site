defmodule DB.ResourceHistoryTest do
  use ExUnit.Case
  import DB.ResourceHistory
  import DB.Factory
  import Ecto.Query

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  doctest DB.ResourceHistory, import: true

  test "test fetch latest resource history payload for a resource" do
    now = DateTime.utc_now()
    past = now |> DateTime.add(-3 * 60)
    pastpast = now |> DateTime.add(-6 * 60)

    %{id: resource_id_1} = insert(:resource)
    insert(:resource_history, %{resource_id: resource_id_1, inserted_at: past})
    insert(:resource_history, %{resource_id: resource_id_1, inserted_at: now})

    %{id: resource_id_2} = insert(:resource)
    insert(:resource_history, %{resource_id: resource_id_2, inserted_at: pastpast})

    insert(:resource_history, %{
      resource_id: resource_id_2,
      inserted_at: past,
      payload: %{"permanent_url" => url = "url"}
    })

    assert %DB.ResourceHistory{payload: %{"permanent_url" => ^url}} = latest_resource_history(resource_id_2)
  end

  test "test fetch latest resource history infos for a dataset" do
    now = DateTime.utc_now()
    past = now |> DateTime.add(-3 * 60)
    pastpast = now |> DateTime.add(-6 * 60)

    dataset = insert(:dataset)

    # wrong dataset
    %{id: resource_id_0} = insert(:resource)
    insert(:resource_history, %{resource_id: resource_id_0, inserted_at: now})

    # no resource history payload
    %{id: resource_id_1} = insert(:resource, dataset: dataset)
    insert(:resource_history, %{resource_id: resource_id_1, inserted_at: now})

    # no filesize in payload
    %{id: resource_id_2} = insert(:resource, dataset: dataset)
    insert(:resource_history, %{resource_id: resource_id_2, inserted_at: pastpast})

    insert(:resource_history, %{
      resource_id: resource_id_2,
      inserted_at: past,
      payload: %{"permanent_url" => r2_url = "r2_url"}
    })

    # all good
    %{id: resource_id_3} = insert(:resource, dataset: dataset)
    insert(:resource_history, %{resource_id: resource_id_3, inserted_at: past})

    insert(:resource_history, %{
      resource_id: resource_id_3,
      inserted_at: now,
      payload: %{"permanent_url" => r3_url = "r3_url", "filesize" => filesize = "10"}
    })

    assert %{
             ^resource_id_1 => %DB.ResourceHistory{resource_id: ^resource_id_1, payload: %{}},
             ^resource_id_2 => %DB.ResourceHistory{resource_id: ^resource_id_2, payload: %{"permanent_url" => ^r2_url}},
             ^resource_id_3 => %DB.ResourceHistory{
               resource_id: ^resource_id_3,
               payload: %{"permanent_url" => ^r3_url, "filesize" => ^filesize}
             }
           } = latest_dataset_resources_history_infos(dataset)
  end

  test "composable query" do
    resource_1 = insert(:resource)
    insert(:resource_history, resource_id: resource_1.id, inserted_at: DateTime.utc_now() |> DateTime.add(-2000))

    latest_resource_history =
      insert(:resource_history, resource_id: resource_1.id, inserted_at: DateTime.utc_now() |> DateTime.add(-1000))

    resource_2 = insert(:resource)
    insert(:resource_history, resource_id: resource_2.id, inserted_at: DateTime.utc_now() |> DateTime.add(-100))

    assert latest_resource_history ==
             DB.Resource.base_query()
             |> DB.Resource.filter_on_resource_id(resource_1.id)
             |> DB.ResourceHistory.join_resource_with_latest_resource_history()
             |> select([resource_history: rh], rh)
             |> DB.Repo.one!()
  end
end
