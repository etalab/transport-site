defmodule Transport.Test.Transport.CounterCacheTest do
  use ExUnit.Case, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "write cache" do
    # First resource with everything good
    %{resource: %{id: resource_id}} = insert_up_to_date_resource_and_friends(modes: ["rollerblades", "bus"])
    # Second resource with empty modes
    %{resource: %{id: resource_empty_metadata}} = insert_up_to_date_resource_and_friends()
    # Third resource has no validation
    %DB.Resource{id: resource_no_validation} = insert(:resource, dataset: insert(:dataset), format: "GTFS")

    Transport.CounterCache.cache_modes_on_resources()

    assert %DB.Resource{counter_cache: %{"gtfs_modes" => ["rollerblades", "bus"]}} =
             DB.Repo.get!(DB.Resource, resource_id)

    assert %DB.Resource{counter_cache: %{"gtfs_modes" => []}} = DB.Repo.get!(DB.Resource, resource_empty_metadata)
    assert %DB.Resource{counter_cache: %{}} = DB.Repo.get!(DB.Resource, resource_no_validation)
  end
end
