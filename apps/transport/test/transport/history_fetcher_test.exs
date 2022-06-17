defmodule Transport.History.FetcherTest do
  use ExUnit.Case, async: true
  import DB.Factory

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "Fetcher.Null" do
    test "history_resources" do
      assert [] == Transport.History.Fetcher.Null.history_resources(insert(:dataset))
    end
  end

  describe "Fetcher.Database" do
    test "history_resources" do
      dataset = insert(:dataset)
      resource = insert(:resource, dataset: dataset)
      other_resource_same_dataset = insert(:resource, dataset: dataset)
      other_resource = insert(:resource, dataset: insert(:dataset))
      insert(:resource_history, resource_id: resource.id, payload: %{})
      insert(:resource_history, resource_id: resource.id, payload: %{"dataset_id" => dataset.id})
      insert(:resource_history, resource_id: other_resource_same_dataset.id, payload: %{"dataset_id" => dataset.id})
      # Should be ignored
      insert(:resource_history, resource_id: other_resource.id, payload: %{})

      assert Enum.count(Transport.History.Fetcher.Database.history_resources(dataset)) == 3
      assert Transport.History.Fetcher.Database.history_resources(insert(:dataset)) == []
    end
  end
end
