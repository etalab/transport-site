defmodule Transport.Test.Transport.Jobs.ResourceUnavailableJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo

  alias DB.{Repo, Resource}
  alias Transport.Jobs.{ResourcesUnavailableDispatcherJob, ResourceUnavailableJob}
  import Ecto.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "ResourcesUnavailableDispatcherJob" do
    test "resources_to_check" do
      resource_id = create_resources()
      assert 4 == count_resources()
      assert [resource_id] == ResourcesUnavailableDispatcherJob.resources_to_check()
    end

    test "a simple successful case" do
      resource_id = create_resources()

      assert count_resources() > 1
      assert :ok == perform_job(ResourcesUnavailableDispatcherJob, %{})
      assert [%{args: %{"resource_id" => ^resource_id}}] = all_enqueued(worker: ResourceUnavailableJob)
      refute_enqueued(worker: ResourcesUnavailableDispatcherJob)
    end
  end

  defp count_resources do
    Repo.one!(from(r in Resource, select: count()))
  end

  defp create_resources do
    %{id: active_dataset_id} = insert(:dataset, is_active: true)
    %{id: inactive_dataset_id} = insert(:dataset, is_active: false)

    %{id: resource_id} =
      insert(:resource,
        url: "https://example.com/gtfs.zip",
        dataset_id: active_dataset_id,
        is_community_resource: false
      )

    # Resources that should be ignored
    insert(:resource,
      url: "https://example.com/gtfs.zip",
      dataset_id: active_dataset_id,
      title: "Ignored because it's a community resource",
      is_community_resource: true
    )

    insert(:resource,
      url: "https://example.com/gtfs.zip",
      dataset_id: inactive_dataset_id,
      title: "Ignored because is not active",
      is_community_resource: false
    )

    insert(:resource,
      url: "ftp://example.com/gtfs.zip",
      dataset_id: active_dataset_id,
      title: "Ignored because is not available over HTTP",
      is_community_resource: false
    )

    resource_id
  end
end
