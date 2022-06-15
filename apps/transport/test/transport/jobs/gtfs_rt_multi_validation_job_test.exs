defmodule Transport.Test.Transport.Jobs.GTFSRTMultiValidationDispatcherJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import Ecto.Query
  import DB.Factory
  import Mox
  alias Transport.Jobs.{GTFSRTMultiValidationDispatcherJob, GTFSRTMultiValidationJob}
  alias Transport.Test.S3TestUtils
  alias Transport.Validators.{GTFSRT, GTFSTransport}

  @gtfs_rt_report_path "#{__DIR__}/../../fixture/files/gtfs-rt-validator-errors.json"
  @validator_filename "gtfs-realtime-validator-lib-1.0.0-SNAPSHOT.jar"

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  @gtfs_validator_name GTFSTransport.validator_name()

  describe "GTFSRTMultiValidationDispatcherJob" do
    test "selects appropriate datasets" do
      dataset = insert(:dataset, is_active: true)

      %{id: resource_id} =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "GTFS"
        )

      %{id: resource_history_id} = insert(:resource_history, resource_id: resource_id)

      %{id: multi_validation_id} =
        insert(:multi_validation, validator: @gtfs_validator_name, resource_history_id: resource_history_id)

      insert(:resource_metadata,
        multi_validation_id: multi_validation_id,
        metadata: %{"start_date" => Date.utc_today() |> Date.add(-30), "end_date" => Date.utc_today() |> Date.add(30)}
      )

      insert(:resource, dataset_id: dataset.id, is_available: true, format: "gtfs-rt")

      # Dataset with an outdated GTFS
      outdated_dataset = insert(:dataset, is_active: true)

      %{id: outdated_resource_id} =
        insert(:resource,
          dataset_id: outdated_dataset.id,
          is_available: true,
          format: "GTFS"
        )

      %{id: outdated_resource_history_id} = insert(:resource_history, resource_id: outdated_resource_id)

      %{id: outdated_multi_validation_id} =
        insert(:multi_validation,
          validator: @gtfs_validator_name,
          resource_history_id: outdated_resource_history_id
        )

      insert(:resource_metadata,
        multi_validation_id: outdated_multi_validation_id,
        metadata: %{"start_date" => Date.utc_today() |> Date.add(-30), "end_date" => Date.utc_today() |> Date.add(-5)}
      )

      insert(:resource, dataset_id: dataset.id, is_available: true, format: "gtfs-rt")

      # Dataset without a gtfs-rt
      static_dataset = insert(:dataset, is_active: true)

      static_resource =
        insert(:resource,
          dataset_id: static_dataset.id,
          is_available: true,
          format: "GTFS"
        )

      %{id: static_resource_history_id} = insert(:resource_history, resource_id: static_resource.id)

      %{id: static_multi_validation_id} =
        insert(:multi_validation, validator: @gtfs_validator_name, resource_history_id: static_resource_history_id)

      insert(:resource_metadata,
        multi_validation_id: static_multi_validation_id,
        metadata: %{"start_date" => Date.utc_today() |> Date.add(-30), "end_date" => Date.utc_today() |> Date.add(30)}
      )

      # Dataset with an unavailable GTFS
      unavailable_dataset = insert(:dataset, is_active: true)

      unavailable_resource =
        insert(:resource,
          dataset_id: unavailable_dataset.id,
          is_available: false,
          format: "GTFS"
        )

      %{id: unavailable_resource_history_id} = insert(:resource_history, resource_id: unavailable_resource.id)

      %{id: unavailable_multi_validation_id} =
        insert(:multi_validation,
          validator: @gtfs_validator_name,
          resource_history_id: unavailable_resource_history_id
        )

      insert(:resource_metadata,
        multi_validation_id: unavailable_multi_validation_id,
        metadata: %{"start_date" => Date.utc_today() |> Date.add(-30), "end_date" => Date.utc_today() |> Date.add(30)}
      )

      insert(:resource, dataset_id: unavailable_dataset.id, is_available: true, format: "gtfs-rt")

      assert [dataset.id] == GTFSRTMultiValidationDispatcherJob.relevant_datasets() |> Enum.map(& &1.id)
    end

    test "enqueues other jobs" do
      %{id: dataset_id} = insert(:dataset, is_active: true)

      %{id: resource_id} =
        insert(:resource,
          dataset_id: dataset_id,
          is_available: true,
          format: "GTFS"
        )

      %{id: resource_history_id} = insert(:resource_history, resource_id: resource_id)

      %{id: multi_validation_id} =
        insert(:multi_validation, validator: @gtfs_validator_name, resource_history_id: resource_history_id)

      insert(:resource_metadata,
        multi_validation_id: multi_validation_id,
        metadata: %{"start_date" => Date.utc_today() |> Date.add(-30), "end_date" => Date.utc_today() |> Date.add(30)}
      )

      insert(:resource, dataset_id: dataset_id, is_available: true, format: "gtfs-rt")

      assert :ok == perform_job(GTFSRTMultiValidationDispatcherJob, %{})
      assert [%Oban.Job{args: %{"dataset_id" => ^dataset_id}}] = all_enqueued(worker: GTFSRTMultiValidationJob)
    end
  end

  describe "GTFSRTValidationJob" do
    test "with a GTFS and 2 GTFS-rt" do
      gtfs_permanent_url = "https://example.com/gtfs.zip"
      gtfs_rt_url = "https://example.com/gtfs-rt"
      gtfs_rt_no_errors_url = "https://example.com/gtfs-rt-no-errors"
      resource_history_uuid = Ecto.UUID.generate()

      dataset = insert(:dataset, is_active: true, datagouv_id: Ecto.UUID.generate())

      %{id: resource_id} =
        gtfs =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "GTFS",
          datagouv_id: Ecto.UUID.generate()
        )

      %{id: resource_history_id} =
        insert(:resource_history,
          resource_id: resource_id,
          payload: %{"format" => "GTFS", "permanent_url" => gtfs_permanent_url, "uuid" => resource_history_uuid}
        )

      %{id: multi_validation_id} =
        insert(:multi_validation, validator: @gtfs_validator_name, resource_history_id: resource_history_id)

      insert(:resource_metadata,
        multi_validation_id: multi_validation_id,
        metadata: %{"start_date" => Date.utc_today() |> Date.add(-30), "end_date" => Date.utc_today() |> Date.add(30)}
      )

      %{id: gtfs_rt_id} =
        gtfs_rt =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "gtfs-rt",
          datagouv_id: Ecto.UUID.generate(),
          url: gtfs_rt_url
        )

      %{id: gtfs_rt_no_errors_id} =
        gtfs_rt_no_errors =
        insert(:resource,
          dataset_id: dataset.id,
          is_available: true,
          format: "gtfs-rt",
          datagouv_id: Ecto.UUID.generate(),
          url: gtfs_rt_no_errors_url
        )

      # insert(:resource_history,
      #   datagouv_id: gtfs.datagouv_id,
      #   payload: %{"format" => "GTFS", "permanent_url" => gtfs_permanent_url, "uuid" => resource_history_uuid}
      # )

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

      gtfs_path = GTFSRTMultiValidationJob.download_path(gtfs)
      gtfs_rt_path = GTFSRTMultiValidationJob.download_path(gtfs_rt)
      gtfs_rt_no_errors_path = GTFSRTMultiValidationJob.download_path(gtfs_rt_no_errors)

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

        File.write!(GTFSRTMultiValidationJob.gtfs_rt_result_path(gtfs_rt), File.read!(@gtfs_rt_report_path))
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

        File.write!(GTFSRTMultiValidationJob.gtfs_rt_result_path(gtfs_rt_no_errors), "[]")
        {:ok, nil}
      end)

      assert :ok == perform_job(GTFSRTMultiValidationJob, %{"dataset_id" => dataset.id})
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

      # gtfs_rt_no_errors = DB.Resource |> preload(:validation) |> DB.Repo.get!(gtfs_rt_no_errors.id)

      assert %{
               validator: @validator_name,
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
               secondary_resource_history_id: ^resource_id,
               max_error: "ERROR"
             } = gtfs_rt_validation

      assert gtfs_rt_permanent_url == Transport.S3.permanent_url(:history, gtfs_rt_filename)

      assert %{
               validator: @validator_name,
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
               secondary_resource_history_id: ^resource_id,
               max_error: nil
             } = gtfs_rt_no_errors

      assert gtfs_rt_no_errors_permanent_url == Transport.S3.permanent_url(:history, gtfs_rt_no_errors_filename)

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
  end

  defp validator_path, do: Path.join(Application.fetch_env!(:transport, :transport_tools_folder), @validator_filename)
end
