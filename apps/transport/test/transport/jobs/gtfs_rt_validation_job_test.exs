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
    test "convert_report" do
      assert %{
               "errors_count" => 124,
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
                   "description" => "Timestamps should be populated for all elements",
                   "error_id" => "W001",
                   "errors" => [
                     "trip_id 17646637 does not have a timestamp",
                     "trip_id 17646540 does not have a timestamp",
                     "trip_id 17646603 does not have a timestamp",
                     "trip_id 17646742 does not have a timestamp",
                     "trip_id 17646839 does not have a timestamp"
                   ],
                   "errors_count" => 39,
                   "severity" => "WARNING",
                   "title" => "timestamp not populated"
                 },
                 %{
                   "description" =>
                     "stop_time_update arrival/departure times between sequential stops should always increase - they should never be the same or decrease.",
                   "error_id" => "E022",
                   "errors" => [
                     "trip_id 17646603 stop_sequence 0 departure_time 15:47:01 (1645454821) is less than previous stop departure_time 15:52:46 (1645455166) - times must increase between two sequential stops",
                     "trip_id 17646603 stop_sequence 0 departure_time 15:47:01 (1645454821) is less than previous stop arrival_time 15:52:46 (1645455166) - times must increase between two sequential stops",
                     "trip_id 17646603 stop_sequence 1 arrival_time 15:47:45 (1645454865) is less than previous stop arrival_time 15:52:46 (1645455166) - times must increase between two sequential stops",
                     "trip_id 17646603 stop_sequence 1 departure_time 15:47:45 (1645454865) is less than previous stop arrival_time 15:52:46 (1645455166) - times must increase between two sequential stops",
                     "trip_id 17646604 stop_sequence 0 departure_time 16:25:00 (1645457100) is less than previous stop departure_time 16:31:11 (1645457471) - times must increase between two sequential stops"
                   ],
                   "errors_count" => 16,
                   "severity" => "ERROR",
                   "title" => "Sequential stop_time_update times are not increasing"
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
                 },
                 %{
                   "description" =>
                     "All stop_time_update stop_sequences in GTFS-realtime data must appear in GTFS stop_times.txt for that trip",
                   "error_id" => "E051",
                   "errors" => [
                     "GTFS-rt trip_id 17646637 contains stop_sequence 0 that does not exist in GTFS stop_times.txt for this trip",
                     "GTFS-rt trip_id 17646540 contains stop_sequence 0 that does not exist in GTFS stop_times.txt for this trip",
                     "GTFS-rt trip_id 17646603 contains stop_sequence 0 that does not exist in GTFS stop_times.txt for this trip",
                     "GTFS-rt trip_id 17646742 contains stop_sequence 0 that does not exist in GTFS stop_times.txt for this trip",
                     "GTFS-rt trip_id 17646839 contains stop_sequence 0 that does not exist in GTFS stop_times.txt for this trip"
                   ],
                   "errors_count" => 39,
                   "severity" => "ERROR",
                   "title" => "GTFS-rt stop_sequence not found in GTFS data"
                 }
               ]
             } == GTFSRTValidationJob.convert_report(@gtfs_rt_report_path)
    end
  end
end
