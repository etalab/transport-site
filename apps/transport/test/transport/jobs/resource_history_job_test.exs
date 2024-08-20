defmodule Transport.Test.Transport.Jobs.ResourceHistoryJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo
  import Ecto.Query
  import Mox
  import Transport.Test.TestUtils

  alias Transport.Jobs.{ResourceHistoryAndValidationDispatcherJob, ResourceHistoryJob}

  doctest ResourceHistoryJob, import: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    Mox.stub_with(Transport.DataVisualization.Mock, Transport.DataVisualization.Impl)
    :ok
  end

  setup :verify_on_exit!

  @gtfs_path "#{__DIR__}/../../../../shared/test/validation/gtfs.zip"
  @gtfs_content File.read!(@gtfs_path)

  def setup_req_mock(resource_url, csv_content, opts \\ []) do
    opts = Keyword.validate!(opts, status: 200)

    Transport.Req.Mock
    |> expect(:get, fn ^resource_url, options ->
      assert options[:compressed] == false
      assert options[:decode_body] == false
      stream = options |> Keyword.fetch!(:into)
      # fake write
      File.write!(stream.path, csv_content)

      response =
        %Req.Response{status: opts[:status], headers: %{}}
        |> Req.Response.put_header("Content-Type", "application/octet-stream")
        |> Req.Response.put_header("x-foo", "bar")

      {:ok, response}
    end)
  end

  def setup_aws_mock(resource_id) do
    Transport.ExAWS.Mock
    # Resource upload
    |> expect(:request!, fn request ->
      bucket_name = Transport.S3.bucket_name(:history)
      assert Map.has_key?(request, :body) == false

      assert %{
               src: %File.Stream{} = _,
               service: :s3,
               path: path,
               bucket: ^bucket_name,
               opts: [acl: :public_read]
             } = request

      assert String.starts_with?(path, "#{resource_id}/#{resource_id}.")
    end)
  end

  describe "ResourceHistoryAndValidationDispatcherJob" do
    test "resources_to_historise" do
      ids = create_resources_for_history()
      assert 9 == count_resources()

      assert MapSet.new(ids) ==
               ResourceHistoryAndValidationDispatcherJob.resources_to_historise() |> Enum.map(& &1.id) |> MapSet.new()
    end

    test "a simple successful case" do
      ids = create_resources_for_history()

      assert count_resources() > 1
      assert :ok == perform_job(ResourceHistoryAndValidationDispatcherJob, %{})

      assert [
               %{args: %{"first_job_args" => %{"resource_id" => first_id}}},
               %{args: %{"first_job_args" => %{"resource_id" => second_id}}}
             ] = all_enqueued(worker: Transport.Jobs.Workflow)

      assert Enum.sort([second_id, first_id]) == Enum.sort(ids)

      refute_enqueued(worker: ResourceHistoryAndValidationDispatcherJob)
    end
  end

  describe "should_store_resource?" do
    test "with an empty or a nil ZIP metadata" do
      refute ResourceHistoryJob.should_store_resource?(%DB.Resource{}, nil)
      refute ResourceHistoryJob.should_store_resource?(%DB.Resource{}, [])
    end

    test "with no ResourceHistory records" do
      assert 0 == count_resource_history()
      assert ResourceHistoryJob.should_store_resource?(%DB.Resource{id: 1}, zip_metadata())
    end

    test "with the latest ResourceHistory matching for a ZIP" do
      %{id: resource_history_id, resource_id: resource_id} =
        resource_history =
        insert(:resource_history,
          resource: insert(:resource),
          payload: %{"zip_metadata" => zip_metadata()}
        )

      assert 1 == count_resource_history()
      assert ResourceHistoryJob.same_resource?(resource_history, zip_metadata())

      assert {false, %{id: ^resource_history_id}} =
               ResourceHistoryJob.should_store_resource?(%DB.Resource{id: resource_id}, zip_metadata())
    end

    test "with the latest ResourceHistory matching for a content hash" do
      content_hash = "hash"

      %{id: resource_history_id, resource_id: resource_id} =
        resource_history =
        insert(:resource_history,
          resource: insert(:resource),
          payload: %{"content_hash" => content_hash}
        )

      assert 1 == count_resource_history()
      assert ResourceHistoryJob.same_resource?(resource_history, content_hash)

      assert {false, %{id: ^resource_history_id}} =
               ResourceHistoryJob.should_store_resource?(%DB.Resource{id: resource_id}, content_hash)
    end

    test "with the latest ResourceHistory matching but for a different resource ID" do
      %{resource_id: resource_id} =
        insert(:resource_history,
          resource: insert(:resource),
          payload: %{"zip_metadata" => zip_metadata()}
        )

      assert 1 == count_resource_history()
      assert ResourceHistoryJob.should_store_resource?(%DB.Resource{id: resource_id + 1}, zip_metadata())
    end

    test "with the second to last ResourceHistory matching" do
      %{resource_id: resource_id, payload: %{"zip_metadata" => zip_metadata}} =
        insert(:resource_history,
          resource: insert(:resource),
          payload: %{"zip_metadata" => zip_metadata()}
        )

      %{id: latest_rh_id} =
        insert(:resource_history,
          resource_id: resource_id,
          payload: %{"zip_metadata" => zip_metadata |> Enum.take(2)}
        )

      assert 2 == count_resource_history()
      assert ResourceHistoryJob.should_store_resource?(%DB.Resource{id: resource_id}, zip_metadata())

      %DB.ResourceHistory{id: latest_rh_id} |> DB.Repo.delete()

      assert {false, _} = ResourceHistoryJob.should_store_resource?(%DB.Resource{id: resource_id}, zip_metadata())
    end

    test "with the latest ResourceHistory not matching for a ZIP" do
      %{resource_id: resource_id} =
        insert(:resource_history,
          resource: insert(:resource),
          payload: %{"zip_metadata" => zip_metadata() |> Enum.take(2)}
        )

      assert 1 == count_resource_history()

      assert ResourceHistoryJob.should_store_resource?(%DB.Resource{id: resource_id}, zip_metadata())
    end

    test "with the latest ResourceHistory not matching" do
      %{resource_id: resource_id} =
        insert(:resource_history, resource: insert(:resource), payload: %{"content_hash" => "foo"})

      assert 1 == count_resource_history()

      assert ResourceHistoryJob.should_store_resource?(%DB.Resource{id: resource_id}, "bar")
    end
  end

  describe "set_of_sha256" do
    test "with atoms" do
      assert MapSet.new([{"bar", "foo"}]) == ResourceHistoryJob.set_of_sha256([%{sha256: "foo", file_name: "bar"}])
    end

    test "with strings" do
      assert MapSet.new([{"bar", "foo"}]) ==
               ResourceHistoryJob.set_of_sha256([%{"sha256" => "foo", "file_name" => "bar"}])
    end

    test "with atoms and strings" do
      assert MapSet.new([{"bar", "foo"}, {"foo", "bar"}]) ==
               ResourceHistoryJob.set_of_sha256([
                 %{"sha256" => "foo", "file_name" => "bar"},
                 %{sha256: "bar", file_name: "foo"}
               ])
    end
  end

  describe "same_resource?" do
    test "successful" do
      assert ResourceHistoryJob.same_resource?(
               %DB.ResourceHistory{payload: %{"zip_metadata" => zip_metadata()}},
               zip_metadata()
             )

      assert ResourceHistoryJob.same_resource?(
               %DB.ResourceHistory{payload: %{"content_hash" => "content_hash"}},
               "content_hash"
             )
    end

    test "failures" do
      # For ZIPs
      refute ResourceHistoryJob.same_resource?(
               %DB.ResourceHistory{payload: %{"zip_metadata" => zip_metadata()}},
               zip_metadata() |> Enum.map(fn m -> Map.put(m, "sha256", "foo") end)
             )

      refute ResourceHistoryJob.same_resource?(
               %DB.ResourceHistory{payload: %{"zip_metadata" => zip_metadata()}},
               zip_metadata() |> Enum.take(2)
             )

      refute ResourceHistoryJob.same_resource?(
               %DB.ResourceHistory{payload: %{"zip_metadata" => zip_metadata() |> Enum.take(2)}},
               zip_metadata()
             )

      refute ResourceHistoryJob.same_resource?(%DB.ResourceHistory{payload: %{"zip_metadata" => zip_metadata()}}, [])

      refute ResourceHistoryJob.same_resource?(
               %DB.ResourceHistory{payload: %{"zip_metadata" => [%{"file_name" => "folder/a.txt", "sha256" => "sha"}]}},
               [%{"file_name" => "a.txt", "sha256" => "sha"}]
             )

      # For regular files
      refute ResourceHistoryJob.same_resource?(%DB.ResourceHistory{payload: %{"content_hash" => "foo"}}, "")
    end
  end

  describe "upload_filename" do
    test "GTFS, ZIP file" do
      resource_id = 42

      assert "#{resource_id}/#{resource_id}.20211202.130534.393187.zip" ==
               ResourceHistoryJob.upload_filename(
                 %DB.Resource{id: resource_id, format: "GTFS"},
                 @gtfs_path,
                 ~U[2021-12-02 13:05:34.393187Z]
               )
    end

    test "CSV file" do
      resource_id = 42
      filepath = Path.join(System.tmp_dir!(), Ecto.UUID.generate())

      File.write!(filepath, "foo")

      assert "#{resource_id}/#{resource_id}.20211202.130534.393187.csv" ==
               ResourceHistoryJob.upload_filename(
                 %DB.Resource{id: resource_id, format: "csv"},
                 filepath,
                 ~U[2021-12-02 13:05:34.393187Z]
               )

      File.rm!(filepath)
    end
  end

  describe "ResourceHistoryJob" do
    test "a simple successful case for a GTFS" do
      resource_url = "https://example.com/gtfs.zip"

      %{
        id: resource_id,
        datagouv_id: datagouv_id,
        dataset_id: dataset_id,
        title: title
      } =
        insert(:resource,
          url: resource_url,
          dataset: insert(:dataset, is_active: true),
          format: "GTFS",
          title: "title",
          datagouv_id: "1",
          is_community_resource: false
        )

      setup_req_mock(resource_url, @gtfs_content)
      setup_aws_mock(resource_id)

      assert 0 == count_resource_history()
      assert :ok == perform_job(ResourceHistoryJob, %{resource_id: resource_id})
      assert 1 == count_resource_history()

      ensure_no_tmp_files!("resource_")

      expected_zip_metadata = zip_metadata()

      assert %DB.ResourceHistory{
               resource_id: ^resource_id,
               datagouv_id: ^datagouv_id,
               payload: %{
                 "filenames" => [
                   "ExportService.checksum.md5",
                   "agency.txt",
                   "calendar.txt",
                   "calendar_dates.txt",
                   "routes.txt",
                   "stop_times.txt",
                   "stops.txt",
                   "transfers.txt",
                   "trips.txt"
                 ],
                 "dataset_id" => ^dataset_id,
                 "format" => "GTFS",
                 "http_headers" => %{"content-type" => "application/octet-stream"},
                 "total_compressed_size" => 2_370,
                 "total_uncompressed_size" => 10_685,
                 "title" => ^title,
                 "filename" => filename,
                 "permanent_url" => permanent_url,
                 "zip_metadata" => ^expected_zip_metadata,
                 "uuid" => _uuid,
                 "download_datetime" => _download_datetime
               },
               last_up_to_date_at: last_up_to_date_at
             } = DB.ResourceHistory |> DB.Repo.one!()

      assert permanent_url == Transport.S3.permanent_url(:history, filename)
      refute is_nil(last_up_to_date_at)
    end

    test "a simple successful case for a CSV" do
      csv_content = "col1,col2\nval1,val2"
      latest_schema_version = "0.4.2"

      %DB.Resource{id: resource_id, dataset_id: dataset_id} =
        insert(:resource,
          url: resource_url = "https://example.com/file.csv",
          latest_url: resource_latest_url = "https://example.com/#{Ecto.UUID.generate()}",
          dataset: insert(:dataset, is_active: true),
          format: "csv",
          title: title = "title",
          is_community_resource: false,
          datagouv_id: datagouv_id = Ecto.UUID.generate(),
          schema_name: schema_name = "etalab/schema-lieux-covoiturage",
          schema_version: schema_version = "0.4.1"
        )

      setup_req_mock(resource_url, csv_content)
      setup_aws_mock(resource_id)

      Transport.Shared.Schemas.Mock
      |> expect(:transport_schemas, 1, fn ->
        %{schema_name => %{"versions" => [%{"version_name" => latest_schema_version}]}}
      end)

      assert 0 == count_resource_history()
      assert :ok == perform_job(ResourceHistoryJob, %{resource_id: resource_id})
      assert 1 == count_resource_history()

      ensure_no_tmp_files!("resource_")

      content_hash = :sha256 |> :crypto.hash(csv_content) |> Base.encode16() |> String.downcase()

      assert %DB.ResourceHistory{
               resource_id: ^resource_id,
               datagouv_id: ^datagouv_id,
               payload: %{
                 "dataset_id" => ^dataset_id,
                 "resource_url" => ^resource_url,
                 "resource_latest_url" => ^resource_latest_url,
                 "format" => "csv",
                 "content_hash" => ^content_hash,
                 "http_headers" => %{"content-type" => "application/octet-stream"},
                 "title" => ^title,
                 "filename" => filename,
                 "permanent_url" => permanent_url,
                 "uuid" => _uuid,
                 "download_datetime" => _download_datetime,
                 "schema_name" => ^schema_name,
                 "schema_version" => ^schema_version,
                 "latest_schema_version_to_date" => ^latest_schema_version
               },
               last_up_to_date_at: last_up_to_date_at
             } = DB.ResourceHistory |> DB.Repo.one!()

      # Prevent a potential mistake when test data or code mix up schema versions
      assert schema_version != latest_schema_version
      assert permanent_url == Transport.S3.permanent_url(:history, filename)
      refute is_nil(last_up_to_date_at)
    end

    test "discards the job when the resource should not be historicised" do
      %DB.Resource{} =
        resource =
        insert(:resource,
          url: "https://example.com/gtfs.zip",
          dataset: insert(:dataset, is_active: true),
          format: "GTFS",
          title: "title",
          is_community_resource: true
        )

      assert DB.Resource.community_resource?(resource)

      assert {:cancel, "Resource should not be historicised"} ==
               perform_job(ResourceHistoryJob, %{resource_id: resource.id})
    end

    test "does not store resource again when it did not change" do
      resource_url = "https://example.com/gtfs.zip"

      %{id: resource_id} =
        insert(:resource,
          url: resource_url,
          dataset: insert(:dataset, is_active: true),
          format: "GTFS",
          title: "title",
          is_community_resource: false
        )

      %{id: resource_history_id, updated_at: updated_at} =
        insert(:resource_history,
          resource_id: resource_id,
          payload: %{"zip_metadata" => zip_metadata()}
        )

      setup_req_mock(resource_url, @gtfs_content)

      assert 1 == count_resource_history()
      assert :ok == perform_job(ResourceHistoryJob, %{resource_id: resource_id})
      assert 1 == count_resource_history()

      # check the updated_at field has been updated.
      assert DB.ResourceHistory
             |> DB.Repo.get!(resource_history_id)
             |> Map.get(:updated_at)
             |> DateTime.diff(updated_at, :microsecond) > 0

      ensure_no_tmp_files!("resource_")
    end

    test "does not crash when there is a server error" do
      resource_url = "https://example.com/gtfs.zip"

      %{id: resource_id} =
        insert(:resource,
          url: resource_url,
          dataset: insert(:dataset, is_active: true),
          format: "GTFS",
          title: "title",
          is_community_resource: false
        )

      setup_req_mock(resource_url, "", status: 500)

      assert 0 == count_resource_history()
      assert :ok == perform_job(ResourceHistoryJob, %{resource_id: resource_id})

      ensure_no_tmp_files!("resource_")
    end
  end

  test "historize and validate job workflow, with options" do
    job =
      Transport.Jobs.ResourceHistoryJob.historize_and_validate_job(%{resource_id: resource_id = 123},
        history_options: [unique: nil],
        validation_custom_args: %{"force_validation" => true}
      )

    assert %{changes: %{args: %{jobs: jobs, first_job_args: %{resource_id: ^resource_id}}}} = job

    assert [
             [Transport.Jobs.ResourceHistoryJob, %{}, %{unique: nil}],
             [Transport.Jobs.ResourceHistoryValidationJob, %{"force_validation" => true}, %{}]
           ] = jobs
  end

  defp create_resources_for_history do
    %DB.Dataset{id: active_dataset_id} = insert(:dataset, is_active: true, type: "public-transit")
    %DB.Dataset{id: hidden_dataset_id} = insert(:dataset, is_active: true, is_hidden: true, type: "public-transit")
    %DB.Dataset{id: inactive_dataset_id} = insert(:dataset, is_active: false, type: "public-transit")

    %{id: id_gtfs} =
      insert(:resource,
        url: "https://example.com/gtfs.zip",
        dataset_id: active_dataset_id,
        format: "GTFS",
        title: "title",
        datagouv_id: "1",
        is_community_resource: false
      )

    # Resources that should be ignored
    insert(:resource,
      url: "https://example.com/gtfs.zip",
      dataset_id: active_dataset_id,
      format: "GTFS",
      title: "Ignored because it's a community resource",
      datagouv_id: "2",
      is_community_resource: true
    )

    insert(:resource,
      url: "https://example.com/gbfs",
      dataset_id: active_dataset_id,
      format: "gbfs",
      title: "Ignored because it's realtime",
      datagouv_id: "3",
      is_community_resource: false
    )

    insert(:resource,
      url: "https://example.com/gtfs.zip",
      dataset_id: inactive_dataset_id,
      format: "GTFS",
      title: "Ignored because is not active",
      datagouv_id: "5",
      is_community_resource: false
    )

    insert(:resource,
      url: "ftp://example.com/gtfs.zip",
      dataset_id: active_dataset_id,
      format: "GTFS",
      title: "Ignored because is not available over HTTP",
      datagouv_id: "6",
      is_community_resource: false
    )

    insert(:resource,
      url: "https://example.com/doc",
      dataset_id: active_dataset_id,
      format: "html",
      type: "documentation",
      title: "Ignored because it's a documentation",
      datagouv_id: "7",
      is_community_resource: false
    )

    insert(:resource,
      url: "https://example.com/file",
      dataset: insert(:dataset, is_active: true, type: "bike-scooter-sharing"),
      format: "GTFS",
      title: "Ignored because the dataset type is bike-scooter-sharing",
      datagouv_id: "8",
      is_community_resource: false
    )

    insert(:resource,
      url: "https://example.com/file",
      dataset: insert(:dataset, is_active: true, type: "charging-stations", custom_tags: ["skip_history"]),
      format: "GTFS",
      title: "Ignored because it has the `skip_history` custom tag",
      datagouv_id: "9",
      is_community_resource: false
    )

    %{id: id_csv} =
      insert(:resource,
        url: "https://example.com/file.csv",
        dataset_id: hidden_dataset_id,
        format: "csv",
        title: "CSV file without a datagouv_id",
        datagouv_id: nil,
        is_community_resource: false
      )

    [id_gtfs, id_csv]
  end

  defp count_resource_history do
    DB.Repo.one!(from(r in DB.ResourceHistory, select: count()))
  end

  defp count_resources do
    DB.Repo.one!(from(r in DB.Resource, select: count()))
  end
end
