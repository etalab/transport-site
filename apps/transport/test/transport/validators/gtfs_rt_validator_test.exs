defmodule Transport.Validators.GTFSRTTest do
  # The trigger refresh_dataset_geographic_view_trigger makes this test
  # unreliable in a concurrent setup.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: DB.Repo
  import Ecto.Query
  import DB.Factory
  alias Transport.Validators.GTFSRT
  import Mox

  doctest Transport.Validators.GTFSRT, import: true

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
              "ignore_shapes" => false,
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

      %{dataset: dataset, resource_history: %{id: resource_history_id}, resource: %{id: gtfs_id} = gtfs} =
        insert_up_to_date_resource_and_friends(
          resource_history_payload: %{
            "format" => "GTFS",
            "permanent_url" => gtfs_permanent_url,
            "uuid" => resource_history_uuid
          }
        )

      %DB.Resource{id: gtfs_rt_id} =
        gtfs_rt =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "gtfs-rt",
          is_community_resource: false,
          url: gtfs_rt_url
        )

      %DB.Resource{id: gtfs_rt_no_errors_id} =
        gtfs_rt_no_errors =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "gtfs-rt",
          is_community_resource: false,
          url: gtfs_rt_no_errors_url
        )

      Transport.Req.Mock
      |> expect(:get, fn ^gtfs_rt_url, [compressed: false, decode_body: false, into: %File.Stream{path: stream_path}] ->
        File.write!(stream_path, body = "gtfs-rt")
        {:ok, %Req.Response{status: 200, body: body}}
      end)

      Transport.Req.Mock
      |> expect(:get, fn ^gtfs_rt_no_errors_url,
                         [compressed: false, decode_body: false, into: %File.Stream{path: stream_path}] ->
        File.write!(stream_path, body = "gtfs-rt")
        {:ok, %Req.Response{status: 200, body: body}}
      end)

      Transport.Req.Mock
      |> expect(:get, fn ^gtfs_permanent_url,
                         [compressed: false, decode_body: false, into: %File.Stream{path: stream_path}] ->
        File.write!(stream_path, "gtfs_content")
        {:ok, %Req.Response{status: 200}}
      end)

      mock_s3_stream_upload(gtfs_rt)
      mock_s3_stream_upload(gtfs_rt_no_errors)

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
        DB.MultiValidation.with_result()
        |> where([mv], mv.resource_id == ^gtfs_rt.id and mv.validator == ^GTFSRT.validator_name())
        |> order_by([mv], desc: mv.inserted_at)
        |> limit(1)
        |> DB.Repo.one!()

      gtfs_rt_no_errors_validation =
        DB.MultiValidation.with_result()
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
               secondary_resource_id: ^gtfs_id,
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
               secondary_resource_id: ^gtfs_id,
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

      %{dataset: dataset, resource_history: %{id: resource_history_id}, resource: %{id: gtfs_id} = gtfs} =
        insert_up_to_date_resource_and_friends(
          resource_history_payload: %{
            "format" => "GTFS",
            "permanent_url" => gtfs_permanent_url,
            "uuid" => resource_history_uuid
          }
        )

      %DB.Resource{id: gtfs_rt_id} =
        gtfs_rt =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "gtfs-rt",
          is_community_resource: false,
          url: gtfs_rt_url
        )

      gtfs_rt_no_errors =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "gtfs-rt",
          is_community_resource: false,
          url: gtfs_rt_no_errors_url
        )

      Transport.Req.Mock
      |> expect(:get, fn ^gtfs_rt_url, [compressed: false, decode_body: false, into: %File.Stream{path: stream_path}] ->
        File.write!(stream_path, body = "gtfs-rt")
        {:ok, %Req.Response{status: 200, body: body}}
      end)

      Transport.Req.Mock
      |> expect(:get, fn ^gtfs_permanent_url,
                         [compressed: false, decode_body: false, into: %File.Stream{path: stream_path}] ->
        File.write!(stream_path, "gtfs_content")
        {:ok, %Req.Response{status: 200}}
      end)

      mock_s3_stream_upload(gtfs_rt)

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
        DB.MultiValidation.with_result()
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
               digest: %{
                 "warnings_count" => 26,
                 "errors_count" => 4
               },
               resource_id: ^gtfs_rt_id,
               secondary_resource_id: ^gtfs_id,
               secondary_resource_history_id: ^resource_history_id,
               max_error: "ERROR"
             } = gtfs_rt_validation

      assert gtfs_rt_permanent_url == Transport.S3.permanent_url(:history, gtfs_rt_filename)

      refute DB.MultiValidation.with_result()
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

      %DB.Resource{} =
        gtfs_rt =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "gtfs-rt",
          is_community_resource: false,
          url: gtfs_rt_url
        )

      Transport.Req.Mock
      |> expect(:get, fn ^gtfs_rt_url, [compressed: false, decode_body: false, into: %File.Stream{path: stream_path}] ->
        File.write!(stream_path, body = "gtfs-rt")
        {:ok, %Req.Response{status: 200, body: body}}
      end)

      Transport.Req.Mock
      |> expect(:get, fn ^gtfs_permanent_url,
                         [compressed: false, decode_body: false, into: %File.Stream{path: stream_path}] ->
        File.write!(stream_path, "gtfs_content")
        {:ok, %Req.Response{status: 200}}
      end)

      mock_s3_stream_upload(gtfs_rt)

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
        DB.MultiValidation.with_result()
        |> where([mv], mv.resource_id == ^gtfs_rt.id and mv.validator == ^GTFSRT.validator_name())
        |> order_by([mv], desc: mv.inserted_at)
        |> limit(1)
        |> DB.Repo.all()

      assert [] == gtfs_rt_validation
    end

    test "when there is a memory error, run the validator another time and ignore shapes" do
      gtfs_permanent_url = "https://example.com/gtfs.zip"
      gtfs_rt_url = "https://example.com/gtfs-rt"

      %{dataset: dataset, resource: gtfs} =
        insert_up_to_date_resource_and_friends(
          resource_history_payload: %{
            "format" => "GTFS",
            "permanent_url" => gtfs_permanent_url,
            "uuid" => Ecto.UUID.generate()
          }
        )

      %DB.Resource{} =
        gtfs_rt =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "gtfs-rt",
          is_community_resource: false,
          url: gtfs_rt_url
        )

      Transport.Req.Mock
      |> expect(:get, fn ^gtfs_rt_url, [compressed: false, decode_body: false, into: %File.Stream{path: stream_path}] ->
        File.write!(stream_path, body = "gtfs-rt")
        {:ok, %Req.Response{status: 200, body: body}}
      end)

      Transport.Req.Mock
      |> expect(:get, fn ^gtfs_permanent_url,
                         [compressed: false, decode_body: false, into: %File.Stream{path: stream_path}] ->
        File.write!(stream_path, "gtfs_content")
        {:ok, %Req.Response{status: 200}}
      end)

      mock_s3_stream_upload(gtfs_rt)

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

        {:error, "Exception in thread main java.lang.OutOfMemoryError: Java heap space"}
      end)

      # Runs the validator another time, this time it should ignore shapes validation
      Transport.Rambo.Mock
      |> expect(:run, fn binary, args, [log: false] ->
        assert binary == "java"
        assert File.exists?(gtfs_path)
        assert File.exists?(gtfs_rt_path)

        assert [
                 "-jar",
                 validator_path(),
                 "-ignoreShapes",
                 "yes",
                 "-gtfs",
                 gtfs_path,
                 "-gtfsRealtimePath",
                 Path.dirname(gtfs_rt_path)
               ] == args

        File.write!(GTFSRT.gtfs_rt_result_path(gtfs_rt), File.read!(@gtfs_rt_report_path))
        {:ok, nil}
      end)

      assert :ok == GTFSRT.validate_and_save(dataset)

      assert DB.MultiValidation.with_result()
             |> where([mv], mv.resource_id == ^gtfs_rt.id and mv.validator == ^GTFSRT.validator_name())
             |> DB.Repo.exists?()

      # No temporary files left
      refute File.exists?(Path.dirname(gtfs_path))
      refute File.exists?(Path.dirname(gtfs_rt_path))
    end
  end

  describe "gtfs_rt_resources" do
    test "with an outdated GTFS and 1 GTFS-RT" do
      %{dataset: dataset} = insert_outdated_resource_and_friends()
      insert(:resource, dataset: dataset, is_available: true, format: "gtfs-rt")
      assert [] == GTFSRT.gtfs_rt_resources(dataset)
    end

    test "with 2 GTFS, a GTFS-RT linked to an outdated one: it uses the up-to-date one" do
      %{dataset: dataset, resource: gtfs_1} = insert_outdated_resource_and_friends()
      %{resource: gtfs_2} = insert_up_to_date_resource_and_friends(dataset: dataset)
      %{id: gtfs_2_id} = gtfs_2

      %DB.Resource{id: gtfs_rt_1_id} =
        gtfs_rt_1 =
        insert(:resource, dataset: dataset, is_available: true, format: "gtfs-rt", is_community_resource: false)

      insert(:resource_related, resource_src: gtfs_rt_1, resource_dst: gtfs_1, reason: :gtfs_rt_gtfs)

      assert [
               {%DB.Resource{id: ^gtfs_2_id}, %DB.Resource{id: ^gtfs_rt_1_id}}
             ] = GTFSRT.gtfs_rt_resources(dataset)
    end

    test "with 2 up-to-date GTFS, 2 GTFS-RT linked to a GTFS, 1 GTFS-RT linked to nothing" do
      %{dataset: dataset, resource: %DB.Resource{id: gtfs_1_id, format: "GTFS"} = gtfs_1} =
        insert_up_to_date_resource_and_friends()

      %{resource: %DB.Resource{format: "GTFS"}} = insert_up_to_date_resource_and_friends(dataset: dataset)

      %DB.Resource{id: gtfs_rt_1_id} =
        gtfs_rt_1 =
        insert(:resource, dataset: dataset, is_available: true, format: "gtfs-rt", is_community_resource: false)

      %DB.Resource{id: gtfs_rt_2_id} =
        gtfs_rt_2 =
        insert(:resource, dataset: dataset, is_available: true, format: "gtfs-rt", is_community_resource: false)

      # Should be ignored because no `resource_related` exists
      _ignored_gtfs_rt = insert(:resource, dataset: dataset, is_available: true, format: "gtfs-rt")

      insert(:resource_related, resource_src: gtfs_rt_1, resource_dst: gtfs_1, reason: :gtfs_rt_gtfs)
      insert(:resource_related, resource_src: gtfs_rt_2, resource_dst: gtfs_1, reason: :gtfs_rt_gtfs)

      assert [
               {%DB.Resource{id: ^gtfs_1_id}, %DB.Resource{id: ^gtfs_rt_1_id}},
               {%DB.Resource{id: ^gtfs_1_id}, %DB.Resource{id: ^gtfs_rt_2_id}}
             ] = GTFSRT.gtfs_rt_resources(dataset)
    end
  end

  defp validator_path, do: Path.join(Application.fetch_env!(:transport, :transport_tools_folder), @validator_filename)

  defp mock_s3_stream_upload(%DB.Resource{id: resource_id}) do
    Transport.Test.S3TestUtils.s3_mock_stream_file(
      start_path: to_string(resource_id),
      bucket: "transport-data-gouv-fr-resource-history-test"
    )
  end
end
