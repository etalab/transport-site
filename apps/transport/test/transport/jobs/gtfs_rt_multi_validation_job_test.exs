defmodule Transport.Test.Transport.Jobs.GTFSRTMultiValidationDispatcherJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  alias Transport.Jobs.{GTFSRTMultiValidationDispatcherJob, GTFSRTMultiValidationJob}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "GTFSRTMultiValidationDispatcherJob" do
    test "selects appropriate datasets" do
      %{dataset: dataset} = insert_up_to_date_resource_and_friends()
      insert(:resource, dataset_id: dataset.id, is_available: true, format: "gtfs-rt")

      # Dataset with an outdated GTFS
      %{dataset: outdated_dataset} = insert_outdated_resource_and_friends()
      insert(:resource, dataset_id: outdated_dataset.id, is_available: true, format: "gtfs-rt")

      # Dataset without a gtfs-rt
      insert_up_to_date_resource_and_friends()

      # Dataset with an unavailable GTFS
      %{dataset: unavailable_dataset} = insert_up_to_date_resource_and_friends(resource_available: false)
      insert(:resource, dataset_id: unavailable_dataset.id, is_available: true, format: "gtfs-rt")

      assert [dataset.id] == GTFSRTMultiValidationDispatcherJob.relevant_datasets() |> Enum.map(& &1.id)
    end

    test "enqueues other jobs" do
      %{dataset: %{id: dataset_id}} = insert_up_to_date_resource_and_friends()

      insert(:resource, dataset_id: dataset_id, is_available: true, format: "gtfs-rt")

      assert :ok == perform_job(GTFSRTMultiValidationDispatcherJob, %{})
      assert [%Oban.Job{args: %{"dataset_id" => ^dataset_id}}] = all_enqueued(worker: GTFSRTMultiValidationJob)
    end
  end
end
