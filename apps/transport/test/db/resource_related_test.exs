defmodule DB.ResourceRelatedTest do
  use ExUnit.Case, async: true
  import DB.Factory

  doctest DB.ResourceRelated, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "can create, load and delete resources_related" do
    %DB.Resource{id: r1_id} = r1 = insert(:resource)
    %DB.Resource{id: r2_id} = insert(:resource)
    insert(:resource_related, resource_src_id: r1_id, resource_dst_id: r2_id, reason: :gtfs_rt_gtfs)

    assert [
             %DB.ResourceRelated{
               resource_src_id: ^r1_id,
               resource_dst_id: ^r2_id,
               reason: :gtfs_rt_gtfs,
               resource_dst: %DB.Resource{id: ^r2_id}
             }
           ] = DB.Repo.preload(r1, resources_related: [:resource_dst]).resources_related

    # When deleting a resource, the `resource_related` row linking to it is deleted as well
    DB.Repo.delete!(r1)
    assert [] == DB.Repo.all(DB.ResourceRelated)
  end
end
