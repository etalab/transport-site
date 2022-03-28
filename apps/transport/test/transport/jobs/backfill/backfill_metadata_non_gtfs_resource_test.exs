defmodule Transport.Jobs.Backfill.ResourceMetadataNonGTFSTest do
  use ExUnit.Case
  import Transport.Jobs.Backfill.ResourceMetadataNonGTFS
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "updates a non GTFS resource" do
    resource =
      insert(:resource, %{
        datagouv_id: "datagouv_id",
        format: "NeTEx",
        metadata: %{
          "modes" => [],
          "end_date" => nil,
          "networks" => [],
          "has_fares" => false,
          "has_shapes" => false,
          "start_date" => nil,
          "lines_count" => 0
        }
      })

    update_resource(resource.id)

    assert is_nil(DB.Repo.reload!(resource).metadata)
  end

  test "leaves GTFS resources alone" do
    resource =
      insert(:resource, %{
        datagouv_id: "datagouv_id",
        format: "GTFS",
        metadata: %{
          "modes" => [],
          "end_date" => nil,
          "networks" => [],
          "has_fares" => false,
          "has_shapes" => false,
          "start_date" => nil,
          "lines_count" => 0
        }
      })

    update_resource(resource.id)
    assert DB.Repo.reload!(resource) == resource
  end
end
