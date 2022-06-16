defmodule Transport.Test.Transport.Jobs.ResourceHistoryJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo
  import Ecto.Query
  import Mox
  import Transport.Test.TestUtils

  alias Transport.Jobs.{ResourceHistoryDispatcherJob, ResourceHistoryJob}

  doctest ResourceHistoryJob, import: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    Mox.stub_with(Transport.DataVisualization.Mock, Transport.DataVisualization.Impl)
    :ok
  end

  setup :verify_on_exit!

  @gtfs_path "#{__DIR__}/../../../../shared/test/validation/gtfs.zip"
  @gtfs_content File.read!(@gtfs_path)

  describe "ResourceHistoryDispatcherJob" do
    test "resources_to_historise" do
      ids = create_resources_for_history()
      assert 6 == count_resources()
      assert ids == ResourceHistoryDispatcherJob.resources_to_historise()
    end

    test "a simple successful case" do
      ids = create_resources_for_history()

      assert count_resources() > 1
      assert :ok == perform_job(ResourceHistoryDispatcherJob, %{})

      assert [%{args: %{"resource_id" => first_id}}, %{args: %{"resource_id" => second_id}}] =
               all_enqueued(worker: ResourceHistoryJob)

      assert [second_id, first_id] == ids

      refute_enqueued(worker: ResourceHistoryDispatcherJob)
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
      assert ResourceHistoryJob.is_same_resource?(resource_history, zip_metadata())

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
      assert ResourceHistoryJob.is_same_resource?(resource_history, content_hash)

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

  describe "is_same_resource?" do
    test "successful" do
      assert ResourceHistoryJob.is_same_resource?(
               %DB.ResourceHistory{payload: %{"zip_metadata" => zip_metadata()}},
               zip_metadata()
             )

      assert ResourceHistoryJob.is_same_resource?(
               %DB.ResourceHistory{payload: %{"content_hash" => "content_hash"}},
               "content_hash"
             )
    end

    test "failures" do
      # For ZIPs
      refute ResourceHistoryJob.is_same_resource?(
               %DB.ResourceHistory{payload: %{"zip_metadata" => zip_metadata()}},
               zip_metadata() |> Enum.map(fn m -> Map.put(m, "sha256", "foo") end)
             )

      refute ResourceHistoryJob.is_same_resource?(
               %DB.ResourceHistory{payload: %{"zip_metadata" => zip_metadata()}},
               zip_metadata() |> Enum.take(2)
             )

      refute ResourceHistoryJob.is_same_resource?(
               %DB.ResourceHistory{payload: %{"zip_metadata" => zip_metadata() |> Enum.take(2)}},
               zip_metadata()
             )

      refute ResourceHistoryJob.is_same_resource?(%DB.ResourceHistory{payload: %{"zip_metadata" => zip_metadata()}}, [])

      refute ResourceHistoryJob.is_same_resource?(
               %DB.ResourceHistory{payload: %{"zip_metadata" => [%{"file_name" => "folder/a.txt", "sha256" => "sha"}]}},
               [%{"file_name" => "a.txt", "sha256" => "sha"}]
             )

      # For regular files
      refute ResourceHistoryJob.is_same_resource?(%DB.ResourceHistory{payload: %{"content_hash" => "foo"}}, "")
    end
  end

  describe "upload_filename" do
    test "it works" do
      resource_id = 42

      assert "#{resource_id}/#{resource_id}.20211202.130534.393187.zip" ==
               ResourceHistoryJob.upload_filename(
                 %DB.Resource{id: resource_id, format: "GTFS"},
                 ~U[2021-12-02 13:05:34.393187Z]
               )

      assert "#{resource_id}/#{resource_id}.20211202.130534.393187.csv" ==
               ResourceHistoryJob.upload_filename(
                 %DB.Resource{id: resource_id, format: "csv"},
                 ~U[2021-12-02 13:05:34.393187Z]
               )
    end
  end

  describe "ResourceHistoryJob" do
    test "a simple successful case for a GTFS" do
      resource_url = "https://example.com/gtfs.zip"

      %{
        id: resource_id,
        datagouv_id: datagouv_id,
        dataset_id: dataset_id,
        title: title,
        content_hash: first_content_hash
      } =
        resource =
        insert(:resource,
          url: resource_url,
          dataset: insert(:dataset, is_active: true),
          format: "GTFS",
          title: "title",
          datagouv_id: "1",
          is_community_resource: false,
          content_hash: "first_hash",
          metadata: %{"foo" => "bar"}
        )

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^resource_url, _headers, options ->
        assert options == [follow_redirect: true]

        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body: @gtfs_content,
           headers: [{"Content-Type", "application/octet-stream"}, {"x-foo", "bar"}]
         }}
      end)

      validator_metadata = %{
        "start_date" => "2021-12-04",
        "end_date" => "2022-04-24",
        "modes" => ["bus"],
        "networks" => ["Autocars RESALP"]
      }

      # Validator should be called because resource was never historicised
      Shared.Validation.Validator.Mock
      |> expect(:validate_from_url, fn ^resource_url ->
        {:ok, %{"validations" => %{}, "metadata" => validator_metadata}}
      end)

      Transport.ExAWS.Mock
      # Resource upload
      |> expect(:request!, fn request ->
        bucket_name = Transport.S3.bucket_name(:history)

        assert %{
                 service: :s3,
                 http_method: :put,
                 path: path,
                 bucket: ^bucket_name,
                 body: @gtfs_content,
                 headers: %{"x-amz-acl" => "public-read"}
               } = request

        assert String.starts_with?(path, "#{resource_id}/#{resource_id}.")
      end)

      assert 0 == count_resource_history()
      assert :ok == perform_job(ResourceHistoryJob, %{resource_id: resource_id})
      assert 1 == count_resource_history()

      ensure_no_tmp_files!("resource_")

      expected_zip_metadata = zip_metadata()

      assert %DB.ResourceHistory{
               id: resource_history_id,
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
                 "resource_metadata" => ^validator_metadata,
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
      %DB.Resource{content_hash: content_hash} = DB.Repo.reload(resource)
      refute content_hash == first_content_hash

      # assert a resource validation is launched
      assert [%{args: %{"resource_history_id" => ^resource_history_id}}] =
               all_enqueued(worker: Transport.Jobs.ResourceHistoryValidationJob)
    end

    test "a simple successful case for a CSV" do
      resource_url = "https://example.com/file.csv"
      csv_content = "col1,col2\nval1,val2"

      %{
        id: resource_id,
        datagouv_id: datagouv_id,
        dataset_id: dataset_id,
        metadata: resource_metadata,
        title: title,
        schema_name: schema_name
      } =
        resource =
        insert(:resource,
          url: resource_url,
          dataset: insert(:dataset, is_active: true),
          format: "csv",
          title: "title",
          is_community_resource: false,
          datagouv_id: Ecto.UUID.generate(),
          metadata: %{"foo" => "bar"},
          schema_name: "etalab/schema-lieux-covoiturage"
        )

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^resource_url, _headers, options ->
        assert options == [follow_redirect: true]

        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body: csv_content,
           headers: [{"Content-Type", "application/octet-stream"}, {"x-foo", "bar"}]
         }}
      end)

      Transport.ExAWS.Mock
      # Resource upload
      |> expect(:request!, fn request ->
        bucket_name = Transport.S3.bucket_name(:history)

        assert %{
                 service: :s3,
                 http_method: :put,
                 path: path,
                 bucket: ^bucket_name,
                 body: ^csv_content,
                 headers: %{"x-amz-acl" => "public-read"}
               } = request

        assert String.starts_with?(path, "#{resource_id}/#{resource_id}.")
      end)

      # Validation according to the schema
      Transport.Shared.Schemas.Mock
      |> expect(:transport_schemas, 1, fn -> %{schema_name => %{}} end)

      Transport.Shared.Schemas.Mock
      |> expect(:schemas_by_type, 1, fn "tableschema" -> %{schema_name => %{}} end)

      validation_result = %{"fake_validation" => "fake_result"}

      Shared.Validation.TableSchemaValidator.Mock
      |> expect(:validate, fn ^schema_name, ^resource_url, nil -> validation_result end)

      assert 0 == count_resource_history()
      assert :ok == perform_job(ResourceHistoryJob, %{resource_id: resource_id})
      assert 1 == count_resource_history()

      ensure_no_tmp_files!("resource_")

      content_hash = :sha256 |> :crypto.hash(csv_content) |> Base.encode16() |> String.downcase()

      expected_metadata =
        Map.merge(resource_metadata, %{
          "validation" =>
            Map.merge(%{"content_hash" => content_hash, "schema_type" => "tableschema"}, validation_result)
        })

      assert %DB.ResourceHistory{
               resource_id: ^resource_id,
               datagouv_id: ^datagouv_id,
               payload: %{
                 "dataset_id" => ^dataset_id,
                 "format" => "csv",
                 "content_hash" => ^content_hash,
                 "http_headers" => %{"content-type" => "application/octet-stream"},
                 "resource_metadata" => ^expected_metadata,
                 "title" => ^title,
                 "filename" => filename,
                 "permanent_url" => permanent_url,
                 "uuid" => _uuid,
                 "download_datetime" => _download_datetime,
                 "schema_name" => ^schema_name,
                 "schema_version" => nil
               },
               last_up_to_date_at: last_up_to_date_at
             } = DB.ResourceHistory |> DB.Repo.one!()

      assert permanent_url == Transport.S3.permanent_url(:history, filename)
      refute is_nil(last_up_to_date_at)

      # No validation but content hash should be set to the file hash
      %DB.Resource{content_hash: content_hash} = DB.Repo.reload(resource)
      assert content_hash == "580fb39789859f7dc29aebe6bdec9666fc8311739a8705fda0916e2907449e17"
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

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^resource_url, _headers, options ->
        assert options == [follow_redirect: true]
        {:ok, %HTTPoison.Response{status_code: 200, body: @gtfs_content, headers: []}}
      end)

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

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^resource_url, _headers, options ->
        assert options == [follow_redirect: true]
        {:ok, %HTTPoison.Response{status_code: 500, body: "", headers: []}}
      end)

      assert 0 == count_resource_history()
      assert :ok == perform_job(ResourceHistoryJob, %{resource_id: resource_id})

      ensure_no_tmp_files!("resource_")
    end
  end

  defp create_resources_for_history do
    %{id: active_dataset_id} = insert(:dataset, is_active: true)
    %{id: inactive_dataset_id} = insert(:dataset, is_active: false)

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

    %{id: id_csv} =
      insert(:resource,
        url: "https://example.com/file.csv",
        dataset_id: active_dataset_id,
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
