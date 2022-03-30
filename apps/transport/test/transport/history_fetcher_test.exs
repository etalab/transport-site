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
      resource = insert(:resource, dataset: dataset, datagouv_id: "foo")
      other_resource = insert(:resource, dataset: insert(:dataset), datagouv_id: "bar")
      insert(:resource_history, datagouv_id: resource.datagouv_id, payload: %{})
      insert(:resource_history, datagouv_id: resource.datagouv_id, payload: %{})
      insert(:resource_history, datagouv_id: "bar", payload: %{"dataset_id" => dataset.id})
      # Should be ignored
      insert(:resource_history, datagouv_id: other_resource.datagouv_id, payload: %{})

      assert Enum.count(Transport.History.Fetcher.Database.history_resources(dataset)) == 3
      assert Transport.History.Fetcher.Database.history_resources(insert(:dataset)) == []
    end
  end
end
