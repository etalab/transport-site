defmodule Transport.Test.Transport.Jobs.ResourceHistoryJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo

  alias Transport.Jobs.{ResourceHistoryJob, ResourceHistoryDispatcherJob}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "ResourceHistoryDispatcherJob" do
    test "a simple successful case" do
      %{datagouv_id: datagouv_id} =
        insert(:resource,
          url: "https://example.com/gtfs.zip",
          format: "GTFS",
          title: "title",
          datagouv_id: "1",
          is_community_resource: false
        )

      # Resources that should be ignored
      insert(:resource,
        url: "https://example.com/gtfs.zip",
        format: "GTFS",
        title: "Ignored because it's a community resource",
        datagouv_id: "2",
        is_community_resource: true
      )

      insert(:resource,
        url: "https://example.com/gbfs",
        format: "gbfs",
        title: "Ignored because it's not GTFS or NeTEx",
        datagouv_id: "3",
        is_community_resource: false
      )

      insert(:resource,
        url: "https://example.com/gtfs.zip",
        format: "GTFS",
        title: "Ignored because of duplicated datagouv_id",
        datagouv_id: "4",
        is_community_resource: false
      )

      insert(:resource,
        url: "https://example.com/gtfs.zip",
        format: "GTFS",
        title: "Ignored because of duplicated datagouv_id",
        datagouv_id: "4",
        is_community_resource: false
      )

      assert :ok == perform_job(ResourceHistoryDispatcherJob, %{})
      assert [%{args: %{"datagouv_id" => ^datagouv_id}}] = all_enqueued(worker: ResourceHistoryJob)
      refute_enqueued(worker: ResourceHistoryDispatcherJob)
    end
  end
end
