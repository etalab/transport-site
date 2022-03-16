defmodule DB.ResourceHistoryTest do
  use ExUnit.Case
  import DB.ResourceHistory
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "test fetch latest resource history payload for a resource" do
    now = DateTime.utc_now()
    past = now |> DateTime.add(-3 * 60)
    pastpast = now |> DateTime.add(-6 * 60)

    insert(:resource, %{datagouv_id: "datagouv_1"})
    insert(:resource_history, %{datagouv_id: "datagouv_1", inserted_at: past})
    insert(:resource_history, %{datagouv_id: "datagouv_1", inserted_at: now})

    %{id: resource_id_2} = insert(:resource, %{datagouv_id: "datagouv_2"})
    insert(:resource_history, %{datagouv_id: "datagouv_2", inserted_at: pastpast})

    insert(:resource_history, %{
      datagouv_id: "datagouv_2",
      inserted_at: past,
      payload: %{"permanent_url" => url = "url"}
    })

    assert %{"permanent_url" => ^url} = latest_resource_history_payload(resource_id_2)
  end

  test "test fetch latest resource history infos for a resource" do
    now = DateTime.utc_now()
    past = now |> DateTime.add(-3 * 60)
    pastpast = now |> DateTime.add(-6 * 60)

    %{id: resource_id_2} = insert(:resource, %{datagouv_id: "datagouv"})
    insert(:resource_history, %{datagouv_id: "datagouv", inserted_at: pastpast})

    insert(:resource_history, %{
      datagouv_id: "datagouv",
      inserted_at: past,
      payload: %{"permanent_url" => url = "url", "file_size" => size = 10}
    })

    assert %{url: url, file_size: size} == latest_resource_history_infos(resource_id_2)

    # new resource history, no file_size
    insert(:resource_history, %{datagouv_id: "datagouv", inserted_at: now, payload: %{"permanent_url" => url}})

    assert is_nil(latest_resource_history_infos(resource_id_2))
  end

  test "test fetch latest resource history infos for a dataset" do
    now = DateTime.utc_now()
    past = now |> DateTime.add(-3 * 60)
    pastpast = now |> DateTime.add(-6 * 60)

    %{id: dataset_id} = insert(:dataset)

    # wrong dataset
    insert(:resource, %{datagouv_id: "datagouv_0"})
    insert(:resource_history, %{datagouv_id: "datagouv_0", inserted_at: now})

    # no resource history payload
    %{id: resource_id_1} = insert(:resource, %{dataset_id: dataset_id, datagouv_id: "datagouv_1"})
    insert(:resource_history, %{datagouv_id: "datagouv_1", inserted_at: now})

    # no file_size in payload
    %{id: resource_id_2} = insert(:resource, %{dataset_id: dataset_id, datagouv_id: "datagouv_2"})
    insert(:resource_history, %{datagouv_id: "datagouv_2", inserted_at: pastpast})

    insert(:resource_history, %{
      datagouv_id: "datagouv_2",
      inserted_at: past,
      payload: %{"permanent_url" => url = "url"}
    })

    # all good
    %{id: resource_id_3} = insert(:resource, %{dataset_id: dataset_id, datagouv_id: "datagouv_3"})
    insert(:resource_history, %{datagouv_id: "datagouv_3", inserted_at: past})

    insert(:resource_history, %{
      datagouv_id: "datagouv_3",
      inserted_at: now,
      payload: %{"permanent_url" => url, "file_size" => file_size = "10"}
    })

    assert %{
             resource_id_1 => %{url: nil, file_size: nil},
             resource_id_2 => %{url: url, file_size: nil},
             resource_id_3 => %{url: url, file_size: file_size}
           } == latest_dataset_resources_history_infos(dataset_id)
  end
end
