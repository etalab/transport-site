defmodule Transport.Jobs.Backfill.ResourceHistoryMetadataNonGTFSTest do
  use ExUnit.Case
  import Transport.Jobs.Backfill.ResourceHistoryMetadataNonGTFS
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "updates a non GTFS ResourceHistory" do
    resource_history =
      insert(:resource_history, %{
        datagouv_id: datagouv_id = "datagouv_id",
        payload: %{
          "format" => "NeTEx",
          "other_field" => "other_value",
          "resource_metadata" => %{
            "modes" => [],
            "end_date" => nil,
            "networks" => [],
            "has_fares" => false,
            "has_shapes" => false,
            "start_date" => nil,
            "lines_count" => 0
          }
        }
      })

    update_resource_history(resource_history.id)

    res = DB.Repo.reload!(resource_history)

    assert res.datagouv_id == datagouv_id
    assert res.payload == %{"format" => "NeTEx", "other_field" => "other_value", "resource_metadata" => nil}
  end

  test "leaves GTFS ResourceHistory alone" do
    resource_history =
      insert(:resource_history, %{
        datagouv_id: "datagouv_id",
        payload: %{
          "format" => "GTFS",
          "other_field" => "other_value",
          "resource_metadata" => %{
            "modes" => [],
            "end_date" => nil,
            "networks" => [],
            "has_fares" => false,
            "has_shapes" => false,
            "start_date" => nil,
            "lines_count" => 0
          }
        }
      })

    update_resource_history(resource_history.id)
    assert DB.Repo.reload!(resource_history) == resource_history
  end
end
