defmodule Transport.Validators.GTFSRTTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import Ecto.Query
  import DB.Factory
  alias Transport.Test.S3TestUtils
  alias Transport.Validators.GTFSRT
  import Mox

  @gtfs_rt_report_path "#{__DIR__}/../../fixture/files/gtfs-rt-validator-errors.json"
  @validator_filename "gtfs-realtime-validator-lib-1.0.0-SNAPSHOT.jar"

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

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

  describe "validate_and_save" do
    test "with a GTFS and 2 GTFS-rt" do
      gtfs_permanent_url = "https://example.com/gtfs.zip"
      gtfs_rt_url = "https://example.com/gtfs-rt"
      gtfs_rt_no_errors_url = "https://example.com/gtfs-rt-no-errors"

      resource_history_uuid = Ecto.UUID.generate()

      %{dataset: dataset, resource_history: %{id: resource_history_id}, resource: gtfs} =
        insert_up_to_date_resource_and_friends(
          resource_history_payload: %{
            "format" => "GTFS",
            "permanent_url" => gtfs_permanent_url,
            "uuid" => resource_history_uuid
          }
        )

      %{id: gtfs_rt_id} =
        gtfs_rt =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "gtfs-rt",
          url: gtfs_rt_url
        )

      %{id: gtfs_rt_no_errors_id} =
        gtfs_rt_no_errors =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "gtfs-rt",
          url: gtfs_rt_no_errors_url
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

      S3TestUtils.s3_mocks_upload_file(gtfs_rt.id |> to_string())
      S3TestUtils.s3_mocks_upload_file(gtfs_rt_no_errors.id |> to_string())

      gtfs_path = GTFSRT.download_path(gtfs)
      gtfs_rt_path = GTFSRT.download_path(gtfs_rt)
      gtfs_rt_no_errors_path = GTFSRT.download_path(gtfs_rt_no_errors)

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

        File.write!(GTFSRT.gtfs_rt_result_path(gtfs_rt), File.read!(@gtfs_rt_report_path))
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

        File.write!(GTFSRT.gtfs_rt_result_path(gtfs_rt_no_errors), "[]")
        {:ok, nil}
      end)

      assert :ok == GTFSRT.validate_and_save(dataset)
      {:ok, report} = GTFSRT.convert_validator_report(@gtfs_rt_report_path)
      expected_errors = Map.fetch!(report, "errors")

      gtfs_rt_validation =
        DB.MultiValidation
        |> where([mv], mv.resource_id == ^gtfs_rt.id and mv.validator == ^GTFSRT.validator_name())
        |> order_by([mv], desc: mv.inserted_at)
        |> limit(1)
        |> DB.Repo.one!()

      gtfs_rt_no_errors_validation =
        DB.MultiValidation
        |> where([mv], mv.resource_id == ^gtfs_rt_no_errors.id and mv.validator == ^GTFSRT.validator_name())
        |> order_by([mv], desc: mv.inserted_at)
        |> limit(1)
        |> DB.Repo.one!()

      validator_name = GTFSRT.validator_name()

      assert %{
               validator: ^validator_name,
               result: %{
                 "errors" => ^expected_errors,
                 "warnings_count" => 26,
                 "errors_count" => 4,
                 "files" => %{
                   "gtfs_permanent_url" => ^gtfs_permanent_url,
                   "gtfs_resource_history_uuid" => ^resource_history_uuid,
                   "gtfs_rt_filename" => gtfs_rt_filename,
                   "gtfs_rt_permanent_url" => gtfs_rt_permanent_url
                 },
                 "has_errors" => true,
                 "uuid" => _uuid
               },
               resource_id: ^gtfs_rt_id,
               secondary_resource_history_id: ^resource_history_id,
               max_error: "ERROR"
             } = gtfs_rt_validation

      assert gtfs_rt_permanent_url == Transport.S3.permanent_url(:history, gtfs_rt_filename)

      assert %{
               validator: ^validator_name,
               result: %{
                 "errors" => [],
                 "warnings_count" => 0,
                 "errors_count" => 0,
                 "files" => %{
                   "gtfs_permanent_url" => ^gtfs_permanent_url,
                   "gtfs_resource_history_uuid" => ^resource_history_uuid,
                   "gtfs_rt_filename" => gtfs_rt_no_errors_filename,
                   "gtfs_rt_permanent_url" => gtfs_rt_no_errors_permanent_url
                 },
                 "has_errors" => false,
                 "uuid" => _uuid
               },
               resource_id: ^gtfs_rt_no_errors_id,
               secondary_resource_history_id: ^resource_history_id,
               max_error: nil
             } = gtfs_rt_no_errors_validation

      assert gtfs_rt_no_errors_permanent_url == Transport.S3.permanent_url(:history, gtfs_rt_no_errors_filename)

      # No temporary files left
      refute File.exists?(Path.dirname(gtfs_path))
      refute File.exists?(Path.dirname(gtfs_rt_path))
      refute File.exists?(Path.dirname(gtfs_rt_no_errors_path))
    end

    test "with a GTFS, 2 GTFS-rt and a resource_id filter" do
      gtfs_permanent_url = "https://example.com/gtfs.zip"
      gtfs_rt_url = "https://example.com/gtfs-rt"
      gtfs_rt_no_errors_url = "https://example.com/gtfs-rt-no-errors"

      resource_history_uuid = Ecto.UUID.generate()

      %{dataset: dataset, resource_history: %{id: resource_history_id}, resource: gtfs} =
        insert_up_to_date_resource_and_friends(
          resource_history_payload: %{
            "format" => "GTFS",
            "permanent_url" => gtfs_permanent_url,
            "uuid" => resource_history_uuid
          }
        )

      %{id: gtfs_rt_id} =
        gtfs_rt =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "gtfs-rt",
          url: gtfs_rt_url
        )

      gtfs_rt_no_errors =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "gtfs-rt",
          url: gtfs_rt_no_errors_url
        )

      Transport.HTTPoison.Mock
      |> expect(:get!, fn ^gtfs_permanent_url, [], [follow_redirect: true] ->
        %HTTPoison.Response{status_code: 200, body: "gtfs"}
      end)

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^gtfs_rt_url, [], [follow_redirect: true] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "gtfs-rt"}}
      end)

      S3TestUtils.s3_mocks_upload_file(gtfs_rt.id |> to_string())

      gtfs_path = GTFSRT.download_path(gtfs)
      gtfs_rt_path = GTFSRT.download_path(gtfs_rt)

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

        File.write!(GTFSRT.gtfs_rt_result_path(gtfs_rt), File.read!(@gtfs_rt_report_path))
        {:ok, nil}
      end)

      assert :ok == GTFSRT.validate_and_save(gtfs_rt)
      {:ok, report} = GTFSRT.convert_validator_report(@gtfs_rt_report_path)
      expected_errors = Map.fetch!(report, "errors")

      gtfs_rt_validation =
        DB.MultiValidation
        |> where([mv], mv.resource_id == ^gtfs_rt.id and mv.validator == ^GTFSRT.validator_name())
        |> order_by([mv], desc: mv.inserted_at)
        |> limit(1)
        |> DB.Repo.one!()

      validator_name = GTFSRT.validator_name()

      assert %{
               validator: ^validator_name,
               result: %{
                 "errors" => ^expected_errors,
                 "warnings_count" => 26,
                 "errors_count" => 4,
                 "files" => %{
                   "gtfs_permanent_url" => ^gtfs_permanent_url,
                   "gtfs_resource_history_uuid" => ^resource_history_uuid,
                   "gtfs_rt_filename" => gtfs_rt_filename,
                   "gtfs_rt_permanent_url" => gtfs_rt_permanent_url
                 },
                 "has_errors" => true,
                 "uuid" => _uuid
               },
               resource_id: ^gtfs_rt_id,
               secondary_resource_history_id: ^resource_history_id,
               max_error: "ERROR"
             } = gtfs_rt_validation

      assert gtfs_rt_permanent_url == Transport.S3.permanent_url(:history, gtfs_rt_filename)

      refute DB.MultiValidation
             |> where([mv], mv.resource_id == ^gtfs_rt_no_errors.id and mv.validator == ^GTFSRT.validator_name())
             |> DB.Repo.exists?()

      # No temporary files left
      refute File.exists?(Path.dirname(gtfs_path))
      refute File.exists?(Path.dirname(gtfs_rt_path))
    end

    test "with a validator error" do
      gtfs_permanent_url = "https://example.com/gtfs.zip"
      gtfs_rt_url = "https://example.com/gtfs-rt"
      validator_message = "io error: entityType=org.onebusaway.gtfs.model.FeedInfo path=feed_info.txt lineNumber=2"

      %{dataset: dataset, resource: gtfs} =
        insert_up_to_date_resource_and_friends(
          resource_history_payload: %{
            "format" => "GTFS",
            "permanent_url" => gtfs_permanent_url,
            "uuid" => Ecto.UUID.generate()
          }
        )

      gtfs_rt =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "gtfs-rt",
          url: gtfs_rt_url
        )

      Transport.HTTPoison.Mock
      |> expect(:get!, fn ^gtfs_permanent_url, [], [follow_redirect: true] ->
        %HTTPoison.Response{status_code: 200, body: "gtfs"}
      end)

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^gtfs_rt_url, [], [follow_redirect: true] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "gtfs-rt"}}
      end)

      S3TestUtils.s3_mocks_upload_file(gtfs_rt.id |> to_string())

      gtfs_path = GTFSRT.download_path(gtfs)
      gtfs_rt_path = GTFSRT.download_path(gtfs_rt)

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

      assert :ok == GTFSRT.validate_and_save(dataset)

      gtfs_rt_validation =
        DB.MultiValidation
        |> where([mv], mv.resource_id == ^gtfs_rt.id and mv.validator == ^GTFSRT.validator_name())
        |> order_by([mv], desc: mv.inserted_at)
        |> limit(1)
        |> DB.Repo.all()

      assert [] == gtfs_rt_validation
    end
  end

  defp validator_path, do: Path.join(Application.fetch_env!(:transport, :transport_tools_folder), @validator_filename)
end
