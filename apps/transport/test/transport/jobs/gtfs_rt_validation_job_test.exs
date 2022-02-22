defmodule Transport.Test.Transport.Jobs.GTFSRTValidationDispatcherJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.{GTFSRTValidationDispatcherJob, GTFSRTValidationJob}

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "GTFSRTValidationDispatcherJob" do
    test "selects appropriate datasets" do
      dataset = insert(:dataset, is_active: true)

      insert(:resource,
        dataset_id: dataset.id,
        is_available: true,
        format: "GTFS",
        start_date: Date.utc_today() |> Date.add(-30),
        end_date: Date.utc_today() |> Date.add(30)
      )

      insert(:resource, dataset_id: dataset.id, is_available: true, format: "gtfs-rt")

      # Dataset with an outdated GTFS
      outdated_dataset = insert(:dataset, is_active: true)

      insert(:resource,
        dataset_id: outdated_dataset.id,
        is_available: true,
        format: "GTFS",
        start_date: Date.utc_today() |> Date.add(-30),
        end_date: Date.utc_today() |> Date.add(-5)
      )

      insert(:resource, dataset_id: outdated_dataset.id, is_available: true, format: "gtfs-rt")

      # Dataset without a gtfs-rt
      static_only_dataset = insert(:dataset, is_active: true)

      insert(:resource,
        dataset_id: static_only_dataset.id,
        is_available: true,
        format: "GTFS",
        start_date: Date.utc_today() |> Date.add(-30),
        end_date: Date.utc_today() |> Date.add(5)
      )

      # Dataset with an unavailable GTFS
      unavailable_dataset = insert(:dataset, is_active: true)

      insert(:resource,
        dataset_id: unavailable_dataset.id,
        is_available: false,
        format: "GTFS",
        start_date: Date.utc_today() |> Date.add(-30),
        end_date: Date.utc_today() |> Date.add(30)
      )

      insert(:resource, dataset_id: unavailable_dataset.id, is_available: true, format: "gtfs-rt")

      assert [dataset.id] == GTFSRTValidationDispatcherJob.relevant_datasets() |> Enum.map(& &1.id)
    end

    test "enqueues other jobs" do
      dataset = insert(:dataset, is_active: true)

      insert(:resource,
        dataset_id: dataset.id,
        is_available: true,
        format: "GTFS",
        start_date: Date.utc_today() |> Date.add(-30),
        end_date: Date.utc_today() |> Date.add(30)
      )

      insert(:resource, dataset_id: dataset.id, is_available: true, format: "gtfs-rt")
      dataset_id = dataset.id

      assert :ok == perform_job(GTFSRTValidationDispatcherJob, %{})
      assert [%Oban.Job{args: %{"dataset_id" => ^dataset_id}}] = all_enqueued(worker: GTFSRTValidationJob)
    end
  end
end
