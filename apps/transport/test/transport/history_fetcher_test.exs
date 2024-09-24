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

      resource_history = insert(:resource_history, resource_id: resource.id, payload: %{})
      mv_1 = insert(:multi_validation, resource_history_id: resource_history.id)
      insert(:resource_metadata, multi_validation_id: mv_1.id, metadata: %{"a" => 1})

      mv_2 = insert(:multi_validation, resource_history_id: resource_history.id)
      insert(:resource_metadata, multi_validation_id: mv_2.id, metadata: %{"a" => 2})

      # resource_id is nil, but dataset_id is filled in the payload => ok
      insert(:resource_history, resource_id: nil, payload: %{"dataset_id" => dataset.id})

      latest_resource_history =
        insert(:resource_history, resource_id: other_resource_same_dataset.id, payload: %{"dataset_id" => dataset.id})

      # Should be ignored
      insert(:resource_history, resource_id: other_resource.id, payload: %{})

      resources_history =
        Transport.History.Fetcher.Database.history_resources(dataset,
          max_records: 25,
          preload_validations: true,
          fetch_mode: :all
        )

      assert length(resources_history) == 3

      # check results are ordered by descending insertion date
      assert resources_history |> Enum.at(0) |> Map.get(:id) == latest_resource_history.id

      # check you can access metadata if present
      rh_with_metadata = resources_history |> Enum.find(&(&1.id == resource_history.id))
      [validation] = rh_with_metadata.validations
      assert validation.metadata.metadata == %{"a" => 2}

      assert Enum.count(
               Transport.History.Fetcher.Database.history_resources(dataset,
                 max_records: 1,
                 preload_validations: true,
                 fetch_mode: :all
               )
             ) == 1

      assert Transport.History.Fetcher.Database.history_resources(insert(:dataset),
               max_records: 25,
               preload_validations: true,
               fetch_mode: :all
             ) == []
    end
  end
end
