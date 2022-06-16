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

  defp insert_resource_and_friends(end_date, opts) do
    def_opts = [resource_available: true, resource_history_payload: %{}]
    opts = Keyword.merge(def_opts, opts)

    dataset = insert(:dataset, is_active: true)

    %{id: resource_id} =
      resource =
      insert(:resource,
        dataset_id: dataset.id,
        is_available: Keyword.get(opts, :resource_available),
        format: "GTFS",
        datagouv_id: Ecto.UUID.generate()
      )

    resource_history =
      insert(:resource_history, resource_id: resource_id, payload: Keyword.get(opts, :resource_history_payload))

    multi_validation =
      insert(:multi_validation, validator: @gtfs_validator_name, resource_history_id: resource_history.id)

    resource_metadata =
      insert(:resource_metadata,
        multi_validation_id: multi_validation.id,
        metadata: %{"start_date" => Date.utc_today() |> Date.add(-30), "end_date" => end_date}
      )

    %{
      dataset: dataset,
      resource: resource,
      resource_history: resource_history,
      multi_validation: multi_validation,
      resource_metadata: resource_metadata
    }
  end

  defp insert_up_to_date_resource_and_friends(opts \\ []) do
    insert_resource_and_friends(Date.utc_today() |> Date.add(30), opts)
  end

  defp insert_outdated_resource_and_friends(opts \\ []) do
    insert_resource_and_friends(Date.utc_today() |> Date.add(-5), opts)
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

  describe "GTFSRTValidationJob" do
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
          datagouv_id: Ecto.UUID.generate(),
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

      S3TestUtils.s3_mocks_upload_file(gtfs_rt.datagouv_id)

      gtfs_path = GTFSRTMultiValidationJob.download_path(gtfs)
      gtfs_rt_path = GTFSRTMultiValidationJob.download_path(gtfs_rt)

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

      assert :ok == perform_job(GTFSRTMultiValidationJob, %{"dataset_id" => dataset.id})

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
