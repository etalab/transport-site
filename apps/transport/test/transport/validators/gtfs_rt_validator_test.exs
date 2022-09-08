defmodule Transport.Validators.GTFSRTTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  alias Transport.Validators.GTFSRT

  @gtfs_rt_report_path "#{__DIR__}/../../fixture/files/gtfs-rt-validator-errors.json"

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "get_max_severity_error" do
    assert nil == GTFSRT.get_max_severity_error([])
    assert "ERROR" == GTFSRT.get_max_severity_error([%{"severity" => "ERROR"}])

    assert "ERROR" ==
             GTFSRT.get_max_severity_error([%{"severity" => "ERROR"}, %{"severity" => "WARNING"}])

    assert "WARNING" == GTFSRT.get_max_severity_error([%{"severity" => "WARNING"}])

    assert_raise RuntimeError, ~r/^Some severity levels are not handled/, fn ->
      GTFSRT.get_max_severity_error([%{"severity" => "foo"}])
    end
  end

  test "convert_validator_report" do
    assert {:ok,
            %{
              "warnings_count" => 26,
              "errors_count" => 4,
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
                  "description" => "Sequential GTFS-rt trip stop_time_updates should never have the same stop_sequence",
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
            }} == GTFSRT.convert_validator_report(@gtfs_rt_report_path)
  end

  test "convert_validator_report when file does not exist" do
    assert :error == GTFSRT.convert_validator_report(Ecto.UUID.generate())
  end

  test "validate_and_save" do
    %{id: gtfs_rt_id, dataset_id: dataset_id} =
      gtfs_rt = insert(:resource, format: "gtfs-rt", dataset: insert(:dataset))

    GTFSRT.validate_and_save(gtfs_rt)

    assert [
             %Oban.Job{
               args: %{"resource_id" => ^gtfs_rt_id, "dataset_id" => ^dataset_id},
               worker: "Transport.Jobs.GTFSRTMultiValidationJob",
               conflict?: false
             }
           ] = all_enqueued()
  end
end
