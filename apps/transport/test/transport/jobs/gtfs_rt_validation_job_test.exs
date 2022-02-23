defmodule Transport.Test.Transport.Jobs.GTFSRTValidationDispatcherJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.{GTFSRTValidationDispatcherJob, GTFSRTValidationJob}

  @gtfs_rt_report_path "#{__DIR__}/../../fixture/files/gtfs-rt-validator-errors.json"

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

  describe "GTFSRTValidationJob" do
    test "get_max_severity_error" do
      assert nil == GTFSRTValidationJob.get_max_severity_error([])
      assert "ERROR" == GTFSRTValidationJob.get_max_severity_error([%{"severity" => "ERROR"}])

      assert "ERROR" ==
               GTFSRTValidationJob.get_max_severity_error([%{"severity" => "ERROR"}, %{"severity" => "WARNING"}])

      assert "WARNING" == GTFSRTValidationJob.get_max_severity_error([%{"severity" => "WARNING"}])

      assert_raise RuntimeError, ~r/^Some severity levels are not handled/, fn ->
        GTFSRTValidationJob.get_max_severity_error([%{"severity" => "foo"}])
      end
    end

    test "convert_validator_report" do
      assert %{
               "errors_count" => 30,
               "has_errors" => true,
               "errors" => [
                 %{
                   "description" => "vehicle_id should be populated for TripUpdates and VehiclePositions",
                   "error_id" => "W002",
                   "errors" => [
                     "trip_id 17646637 does not have a vehicle_id",
                     "trip_id 17646540 does not have a vehicle_id",
                     "trip_id 17646839 does not have a vehicle_id",
                     "trip_id 17646810 does not have a vehicle_id",
                     "trip_id 17646604 does not have a vehicle_id"
                   ],
                   "errors_count" => 26,
                   "severity" => "WARNING",
                   "title" => "vehicle_id not populated"
                 },
                 %{
                   "description" =>
                     "stop_time_updates for a given trip_id must be strictly sorted by increasing stop_sequence",
                   "error_id" => "E002",
                   "errors" => [
                     "trip_id 17646603 stop_sequence [5, 0] is not strictly sorted by increasing stop_sequence",
                     "trip_id 17646604 stop_sequence [5, 0] is not strictly sorted by increasing stop_sequence"
                   ],
                   "errors_count" => 2,
                   "severity" => "ERROR",
                   "title" => "stop_times_updates not strictly sorted"
                 },
                 %{
                   "description" =>
                     "Sequential GTFS-rt trip stop_time_updates should never have the same stop_sequence",
                   "error_id" => "E036",
                   "errors" => [
                     "trip_id 17646603 has repeating stop_sequence 0 - stop_sequence must increase for each stop_time_update",
                     "trip_id 17646604 has repeating stop_sequence 0 - stop_sequence must increase for each stop_time_update"
                   ],
                   "errors_count" => 2,
                   "severity" => "ERROR",
                   "title" => "Sequential stop_time_updates have the same stop_sequence"
                 }
               ]
             } == GTFSRTValidationJob.convert_validator_report(@gtfs_rt_report_path)
    end
  end
end
