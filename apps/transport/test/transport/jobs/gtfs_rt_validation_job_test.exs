defmodule Transport.Test.Transport.Jobs.GTFSRTValidationDispatcherJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import Ecto.Query
  import DB.Factory
  import Mox
  alias Transport.Jobs.{GTFSRTValidationDispatcherJob, GTFSRTValidationJob}
  alias Transport.Test.S3TestUtils

  @gtfs_rt_report_path "#{__DIR__}/../../fixture/files/gtfs-rt-validator-errors.json"
  @validator_filename "gtfs-realtime-validator-lib-1.0.0-SNAPSHOT.jar"

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
    test "with a GTFS and 2 GTFS-rt" do
      gtfs_permanent_url = "https://example.com/gtfs.zip"
      gtfs_rt_url = "https://example.com/gtfs-rt"
      gtfs_rt_no_errors_url = "https://example.com/gtfs-rt-no-errors"
      resource_history_uuid = Ecto.UUID.generate()
      dataset = insert(:dataset, is_active: true, datagouv_id: Ecto.UUID.generate())

      gtfs =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "GTFS",
          start_date: Date.utc_today() |> Date.add(-30),
          end_date: Date.utc_today() |> Date.add(30),
          datagouv_id: Ecto.UUID.generate(),
          metadata: %{
            "start_date" => Date.utc_today() |> Date.add(-30),
            "end_date" => Date.utc_today() |> Date.add(30)
          }
        )

      gtfs_rt =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "gtfs-rt",
          datagouv_id: Ecto.UUID.generate(),
          url: gtfs_rt_url,
          metadata: %{"foo" => "bar"}
        )

      gtfs_rt_no_errors =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "gtfs-rt",
          datagouv_id: Ecto.UUID.generate(),
          url: gtfs_rt_no_errors_url,
          metadata: %{"bar" => "baz"}
        )

      insert(:resource_history,
        datagouv_id: gtfs.datagouv_id,
        payload: %{"format" => "GTFS", "permanent_url" => gtfs_permanent_url, "uuid" => resource_history_uuid}
      )

      Transport.HTTPoison.Mock
      |> expect(:get!, fn ^gtfs_permanent_url, [], [follow_redirect: true] ->
        %HTTPoison.Response{status_code: 200, body: "gtfs"}
      end)

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^gtfs_rt_url, [], [follow_redirect: true] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "gtfs-rt"}}
      end)

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^gtfs_rt_no_errors_url, [], [follow_redirect: true] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "gtfs-rt"}}
      end)

      S3TestUtils.s3_mocks_upload_file(gtfs_rt.datagouv_id)
      S3TestUtils.s3_mocks_upload_file(gtfs_rt_no_errors.datagouv_id)

      gtfs_path = GTFSRTValidationJob.download_path(gtfs)
      gtfs_rt_path = GTFSRTValidationJob.download_path(gtfs_rt)
      gtfs_rt_no_errors_path = GTFSRTValidationJob.download_path(gtfs_rt_no_errors)

      Transport.Rambo.Mock
      |> expect(:run, fn binary, args, [log: false] ->
        assert binary == "java"
        assert File.exists?(gtfs_path)
        assert File.exists?(gtfs_rt_path)

        assert [
                 "-jar",
                 validator_path(),
                 "-gtfs",
                 gtfs_path,
                 "-gtfsRealtimePath",
                 Path.dirname(gtfs_rt_path)
               ] == args

        File.write!(GTFSRTValidationJob.gtfs_rt_result_path(gtfs_rt), File.read!(@gtfs_rt_report_path))
        {:ok, nil}
      end)

      Transport.Rambo.Mock
      |> expect(:run, fn binary, args, [log: false] ->
        assert binary == "java"
        assert File.exists?(gtfs_path)
        assert File.exists?(gtfs_rt_no_errors_path)

        assert [
                 "-jar",
                 validator_path(),
                 "-gtfs",
                 gtfs_path,
                 "-gtfsRealtimePath",
                 Path.dirname(gtfs_rt_no_errors_path)
               ] == args

        File.write!(GTFSRTValidationJob.gtfs_rt_result_path(gtfs_rt_no_errors), "[]")
        {:ok, nil}
      end)

      assert :ok == perform_job(GTFSRTValidationJob, %{"dataset_id" => dataset.id})
      {:ok, report} = GTFSRTValidationJob.convert_validator_report(@gtfs_rt_report_path)
      expected_errors = Map.fetch!(report, "errors")

      gtfs_rt = DB.Resource |> preload(:validation) |> DB.Repo.get!(gtfs_rt.id)
      gtfs_rt_no_errors = DB.Resource |> preload(:validation) |> DB.Repo.get!(gtfs_rt_no_errors.id)

      assert %{
               validation: %DB.Validation{
                 details: %{
                   "validator" => "Elixir.Transport.Jobs.GTFSRTValidationJob",
                   "warnings_count" => 26,
                   "errors_count" => 4,
                   "has_errors" => true,
                   "errors" => ^expected_errors,
                   "files" => validation_files
                 },
                 max_error: "ERROR"
               },
               metadata: %{
                 "foo" => "bar",
                 "validation" => %{
                   "datetime" => _datetime,
                   "errors" => ^expected_errors,
                   "validator" => "Elixir.Transport.Jobs.GTFSRTValidationJob",
                   "warnings_count" => 26,
                   "errors_count" => 4,
                   "files" =>
                     %{
                       "gtfs_permanent_url" => ^gtfs_permanent_url,
                       "gtfs_resource_history_uuid" => ^resource_history_uuid,
                       "gtfs_rt_filename" => gtfs_rt_filename,
                       "gtfs_rt_permanent_url" => gtfs_rt_permanent_url
                     } = files,
                   "has_errors" => true,
                   "max_severity" => "ERROR",
                   "uuid" => _uuid
                 }
               }
             } = gtfs_rt

      assert validation_files == files
      assert gtfs_rt_permanent_url == Transport.S3.permanent_url(:history, gtfs_rt_filename)

      assert %{
               validation: %DB.Validation{
                 details: %{
                   "validator" => "Elixir.Transport.Jobs.GTFSRTValidationJob",
                   "errors_count" => 0,
                   "has_errors" => false,
                   "errors" => [],
                   "files" => validation_files
                 },
                 max_error: nil
               },
               metadata: %{
                 "bar" => "baz",
                 "validation" => %{
                   "datetime" => _datetime,
                   "validator" => "Elixir.Transport.Jobs.GTFSRTValidationJob",
                   "errors" => [],
                   "errors_count" => 0,
                   "warnings_count" => 0,
                   "files" =>
                     %{
                       "gtfs_permanent_url" => ^gtfs_permanent_url,
                       "gtfs_resource_history_uuid" => ^resource_history_uuid,
                       "gtfs_rt_filename" => gtfs_rt_no_errors_filename,
                       "gtfs_rt_permanent_url" => gtfs_rt_no_errors_permanent_url
                     } = files,
                   "has_errors" => false,
                   "max_severity" => nil,
                   "uuid" => _uuid
                 }
               }
             } = gtfs_rt_no_errors

      assert validation_files == files
      assert gtfs_rt_no_errors_permanent_url == Transport.S3.permanent_url(:history, gtfs_rt_no_errors_filename)

      # We've got validation logs
      logs = DB.LogsValidation |> where([l], l.is_success and is_nil(l.error_msg)) |> DB.Repo.all()
      assert DB.Repo.one!(from(r in DB.LogsValidation, select: count())) == 2
      assert Enum.count(logs) == 2
      assert [gtfs_rt.id, gtfs_rt_no_errors.id] == logs |> Enum.map(& &1.resource_id)

      # No temporary files left
      refute File.exists?(Path.dirname(gtfs_path))
      refute File.exists?(Path.dirname(gtfs_rt_path))
      refute File.exists?(Path.dirname(gtfs_rt_no_errors_path))
    end

    test "with a validator error" do
      gtfs_permanent_url = "https://example.com/gtfs.zip"
      gtfs_rt_url = "https://example.com/gtfs-rt"
      validator_message = "io error: entityType=org.onebusaway.gtfs.model.FeedInfo path=feed_info.txt lineNumber=2"
      dataset = insert(:dataset, is_active: true, datagouv_id: Ecto.UUID.generate())

      gtfs =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "GTFS",
          start_date: Date.utc_today() |> Date.add(-30),
          end_date: Date.utc_today() |> Date.add(30),
          datagouv_id: Ecto.UUID.generate(),
          metadata: %{
            "start_date" => Date.utc_today() |> Date.add(-30),
            "end_date" => Date.utc_today() |> Date.add(30)
          }
        )

      gtfs_rt =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "gtfs-rt",
          datagouv_id: Ecto.UUID.generate(),
          url: gtfs_rt_url,
          metadata: %{"foo" => "bar"}
        )

      insert(:resource_history,
        datagouv_id: gtfs.datagouv_id,
        payload: %{"format" => "GTFS", "permanent_url" => gtfs_permanent_url, "uuid" => Ecto.UUID.generate()}
      )

      Transport.HTTPoison.Mock
      |> expect(:get!, fn ^gtfs_permanent_url, [], [follow_redirect: true] ->
        %HTTPoison.Response{status_code: 200, body: "gtfs"}
      end)

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^gtfs_rt_url, [], [follow_redirect: true] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "gtfs-rt"}}
      end)

      S3TestUtils.s3_mocks_upload_file(gtfs_rt.datagouv_id)

      gtfs_path = GTFSRTValidationJob.download_path(gtfs)
      gtfs_rt_path = GTFSRTValidationJob.download_path(gtfs_rt)

      Transport.Rambo.Mock
      |> expect(:run, fn binary, args, [log: false] ->
        assert binary == "java"
        assert File.exists?(gtfs_path)
        assert File.exists?(gtfs_rt_path)

        assert [
                 "-jar",
                 validator_path(),
                 "-gtfs",
                 gtfs_path,
                 "-gtfsRealtimePath",
                 Path.dirname(gtfs_rt_path)
               ] == args

        {:error, validator_message}
      end)

      assert :ok == perform_job(GTFSRTValidationJob, %{"dataset_id" => dataset.id})

      gtfs_rt = DB.Resource |> preload([:validation, :logs_validation]) |> DB.Repo.get!(gtfs_rt.id)

      assert %{metadata: %{"foo" => "bar"}} = gtfs_rt
      assert is_nil(gtfs_rt.validation)

      assert Enum.count(gtfs_rt.logs_validation) == 1

      expected_message = ~s(error while calling the validator: "#{validator_message}")
      assert %DB.LogsValidation{error_msg: ^expected_message, is_success: false} = hd(gtfs_rt.logs_validation)
    end

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
      assert {:ok,
              %{
                "validator" => "Elixir.Transport.Jobs.GTFSRTValidationJob",
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
              }} == GTFSRTValidationJob.convert_validator_report(@gtfs_rt_report_path)
    end
  end

  test "convert_validator_report when file does not exist" do
    assert :error == GTFSRTValidationJob.convert_validator_report(Ecto.UUID.generate())
  end

  defp validator_path, do: Path.join(Application.fetch_env!(:transport, :transport_tools_folder), @validator_filename)
end
