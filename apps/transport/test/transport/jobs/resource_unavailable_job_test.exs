defmodule Transport.Test.Transport.Jobs.ResourceUnavailableJobTest do
  # Cannot be async because we change envs
  use ExUnit.Case, async: false
  import DB.Factory
  use Oban.Testing, repo: DB.Repo

  alias DB.{Repo, Resource, ResourceUnavailability}
  alias Transport.Jobs.{ResourcesUnavailableDispatcherJob, ResourceUnavailableJob}
  import Ecto.Query
  import Mox

  setup :verify_on_exit!

  @resource_url "https://example.com/gtfs.zip"

  setup do
    old_value = Application.fetch_env!(:transport, :availability_checker_impl)
    on_exit(fn -> Application.put_env(:transport, :availability_checker_impl, old_value) end)
    Application.put_env(:transport, :availability_checker_impl, Transport.AvailabilityChecker.Mock)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "ResourcesUnavailableDispatcherJob" do
    test "resources_to_check with not only unavailable" do
      resource_id = create_resources()
      assert 4 == count_resources()
      assert [resource_id] == ResourcesUnavailableDispatcherJob.resources_to_check(false)
    end

    test "resources_to_check with only unavailable" do
      assert [] == ResourcesUnavailableDispatcherJob.resources_to_check(true)

      resource = insert(:resource)
      insert(:resource_unavailability, resource: resource, start: hours_ago(5))
      assert [resource.id] == ResourcesUnavailableDispatcherJob.resources_to_check(true)
    end

    test "a simple successful case" do
      resource_id = create_resources()

      assert count_resources() > 1
      assert :ok == perform_job(ResourcesUnavailableDispatcherJob, %{})
      assert [%{args: %{"resource_id" => ^resource_id}}] = all_enqueued(worker: ResourceUnavailableJob)
      refute_enqueued(worker: ResourcesUnavailableDispatcherJob)
    end
  end

  describe "ResourceUnavailableJob" do
    test "when there is no unavailabilities" do
      assert 0 == count_resource_unavailabilities()
      resource = insert(:resource, url: @resource_url)
      resource_id = resource.id

      setup_mock_unavailable()

      assert :ok == perform_job(ResourceUnavailableJob, %{"resource_id" => resource_id})

      assert 1 == count_resource_unavailabilities()
      %ResourceUnavailability{resource_id: ^resource_id, start: start, end: nil} = ResourceUnavailability |> Repo.one!()
      assert DateTime.diff(DateTime.utc_now(), start) <= 1
    end

    test "when there is an ongoing unavailability and the resource stays unavailable" do
      resource = insert(:resource, url: @resource_url)
      resource_id = resource.id
      start = 2 |> hours_ago()
      insert(:resource_unavailability, resource: resource, start: start)
      assert 1 == count_resource_unavailabilities()

      setup_mock_unavailable()

      assert :ok == perform_job(ResourceUnavailableJob, %{"resource_id" => resource_id})

      %ResourceUnavailability{resource_id: ^resource_id, start: ^start, end: nil} =
        ResourceUnavailability |> Repo.one!()
    end

    test "when there is an ongoing unavailability and the resource is now available" do
      resource = insert(:resource, url: @resource_url)
      resource_id = resource.id
      start = 2 |> hours_ago()
      insert(:resource_unavailability, resource: resource, start: start)
      assert 1 == count_resource_unavailabilities()

      setup_mock_available()

      assert :ok == perform_job(ResourceUnavailableJob, %{"resource_id" => resource_id})

      %ResourceUnavailability{resource_id: ^resource_id, start: ^start, end: date_end} =
        ResourceUnavailability |> Repo.one!()

      assert DateTime.diff(DateTime.utc_now(), date_end) <= 1
    end

    test "when there is no unavailabilities and the resource is available" do
      resource = insert(:resource, url: @resource_url)
      assert 0 == count_resource_unavailabilities()

      setup_mock_available()
      assert :ok == perform_job(ResourceUnavailableJob, %{"resource_id" => resource.id})

      assert 0 == count_resource_unavailabilities()
    end
  end

  defp setup_mock_unavailable do
    url = @resource_url

    Transport.AvailabilityChecker.Mock
    |> expect(:available?, fn ^url -> false end)
  end

  defp setup_mock_available do
    url = @resource_url

    Transport.AvailabilityChecker.Mock
    |> expect(:available?, fn ^url -> true end)
  end

  defp count_resources do
    Repo.one!(from(r in Resource, select: count()))
  end

  defp count_resource_unavailabilities do
    Repo.one!(from(r in ResourceUnavailability, select: count()))
  end

  defp hours_ago(hours) when hours > 0 do
    DateTime.utc_now() |> DateTime.add(-hours * 60 * 60, :second) |> DateTime.truncate(:second)
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
