defmodule Transport.Test.Transport.Jobs.ResourceHistoryJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo
  import Ecto.Query
  import Mox

  alias Transport.Jobs.{ResourceHistoryDispatcherJob, ResourceHistoryJob}
  alias Transport.Test.S3TestUtils

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    DB.Repo.delete_all(DB.ResourceHistory)
    :ok
  end

  setup :verify_on_exit!

  @gtfs_path "#{__DIR__}/../../../../shared/test/validation/gtfs.zip"
  @gtfs_content File.read!(@gtfs_path)

  describe "ResourceHistoryDispatcherJob" do
    test "resources_to_historise" do
      datagouv_id = create_resources_for_history()
      assert 7 == count_resources()
      assert [datagouv_id] == ResourceHistoryDispatcherJob.resources_to_historise()
    end

    test "a simple successful case" do
      S3TestUtils.s3_mocks_create_bucket()
      datagouv_id = create_resources_for_history()

      assert count_resources() > 1
      assert :ok == perform_job(ResourceHistoryDispatcherJob, %{})
      assert [%{args: %{"datagouv_id" => ^datagouv_id}}] = all_enqueued(worker: ResourceHistoryJob)
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
      assert ResourceHistoryJob.should_store_resource?(%DB.Resource{datagouv_id: "1"}, zip_metadata())
    end

    test "with the latest ResourceHistory matching" do
      %{id: resource_history_id, datagouv_id: datagouv_id} =
        resource_history =
        insert(:resource_history,
          datagouv_id: "1",
          payload: %{"zip_metadata" => zip_metadata()}
        )

      assert 1 == count_resource_history()
      assert ResourceHistoryJob.is_same_resource?(resource_history, zip_metadata())
      assert {false, %{id: ^resource_history_id}} = ResourceHistoryJob.should_store_resource?(%DB.Resource{datagouv_id: datagouv_id}, zip_metadata())
    end

    test "with the latest ResourceHistory matching but for a different datagouv_id" do
      %{datagouv_id: datagouv_id} =
        insert(:resource_history,
          datagouv_id: "1",
          payload: %{"zip_metadata" => zip_metadata()}
        )

      assert 1 == count_resource_history()
      assert ResourceHistoryJob.should_store_resource?(%DB.Resource{datagouv_id: "#{datagouv_id}foo"}, zip_metadata())
    end

    test "with the second to last ResourceHistory matching" do
      %{datagouv_id: datagouv_id, payload: %{"zip_metadata" => zip_metadata}} =
        insert(:resource_history,
          datagouv_id: "1",
          payload: %{"zip_metadata" => zip_metadata()}
        )

      %{id: latest_rh_id} =
        insert(:resource_history,
          datagouv_id: datagouv_id,
          payload: %{"zip_metadata" => zip_metadata |> Enum.take(2)}
        )

      assert 2 == count_resource_history()
      assert ResourceHistoryJob.should_store_resource?(%DB.Resource{datagouv_id: datagouv_id}, zip_metadata())

      %DB.ResourceHistory{id: latest_rh_id} |> DB.Repo.delete()
      assert {false, _} =  ResourceHistoryJob.should_store_resource?(%DB.Resource{datagouv_id: datagouv_id}, zip_metadata())
    end

    test "with the latest ResourceHistory not matching" do
      %{datagouv_id: datagouv_id} =
        insert(:resource_history,
          datagouv_id: "1",
          payload: %{"zip_metadata" => zip_metadata() |> Enum.take(2)}
        )

      assert 1 == count_resource_history()

      assert ResourceHistoryJob.should_store_resource?(%DB.Resource{datagouv_id: datagouv_id}, zip_metadata())
    end
  end

  describe "set_of_sha256" do
    test "with atoms" do
      assert MapSet.new(["foo"]) == ResourceHistoryJob.set_of_sha256([%{sha256: "foo"}])
    end

    test "with strings" do
      assert MapSet.new(["foo"]) == ResourceHistoryJob.set_of_sha256([%{"sha256" => "foo"}])
    end

    test "with atoms and strings" do
      assert MapSet.new(["foo", "bar"]) == ResourceHistoryJob.set_of_sha256([%{"sha256" => "foo"}, %{sha256: "bar"}])
    end
  end

  describe "is_same_resource?" do
    test "successful" do
      assert ResourceHistoryJob.is_same_resource?(
               %DB.ResourceHistory{payload: %{"zip_metadata" => zip_metadata()}},
               zip_metadata()
             )
    end

    test "failures" do
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
    end
  end

  describe "upload_filename" do
    test "it works" do
      assert "foo/foo.20211202.130534.393187.zip" ==
               ResourceHistoryJob.upload_filename(%DB.Resource{datagouv_id: "foo"}, ~U[2021-12-02 13:05:34.393187Z])
    end
  end

  describe "ResourceHistoryJob" do
    test "a simple successful case" do
      resource_url = "https://example.com/gtfs.zip"

      %{datagouv_id: datagouv_id, metadata: resource_metadata} =
        insert(:resource,
          url: resource_url,
          dataset: insert(:dataset, is_active: true),
          format: "GTFS",
          title: "title",
          datagouv_id: "1",
          is_community_resource: false,
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

        assert String.starts_with?(path, "#{datagouv_id}/#{datagouv_id}.")
      end)

      assert 0 == count_resource_history()
      assert :ok == perform_job(ResourceHistoryJob, %{datagouv_id: datagouv_id})
      assert 1 == count_resource_history()

      Transport.Test.TestUtils.ensure_no_tmp_files!("resource_")

      expected_zip_metadata = zip_metadata()

      assert %DB.ResourceHistory{
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
                 "format" => "GTFS",
                 "http_headers" => %{"content-type" => "application/octet-stream"},
                 "resource_metadata" => ^resource_metadata,
                 "total_compressed_size" => 2_370,
                 "total_uncompressed_size" => 10_685,
                 "filename" => filename,
                 "permanent_url" => permanent_url,
                 "zip_metadata" => ^expected_zip_metadata,
                 "uuid" => _uuid,
                 "download_datetime" => _download_datetime
               }
             } = DB.ResourceHistory |> DB.Repo.one!()

      assert permanent_url == Transport.S3.permanent_url(:history, filename)
    end

    test "does not store resource again when it did not change" do
      resource_url = "https://example.com/gtfs.zip"

      %{datagouv_id: datagouv_id} =
        insert(:resource,
          url: resource_url,
          dataset: insert(:dataset, is_active: true),
          format: "GTFS",
          title: "title",
          datagouv_id: "1",
          is_community_resource: false
        )

      %{id: resource_history_id, updated_at: updated_at} = insert(:resource_history,
        datagouv_id: datagouv_id,
        payload: %{"zip_metadata" => zip_metadata()}
      )

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^resource_url, _headers, options ->
        assert options == [follow_redirect: true]
        {:ok, %HTTPoison.Response{status_code: 200, body: @gtfs_content, headers: []}}
      end)

      assert 1 == count_resource_history()
      assert :ok == perform_job(ResourceHistoryJob, %{datagouv_id: datagouv_id})
      assert 1 == count_resource_history()

      # check the updated_at field has been updated.
      assert DB.ResourceHistory |> DB.Repo.get!(resource_history_id) |> Map.get(:updated_at) |> DateTime.diff(updated_at, :microsecond) > 0

      Transport.Test.TestUtils.ensure_no_tmp_files!("resource_")
    end

    test "does not crash when there is a server error" do
      resource_url = "https://example.com/gtfs.zip"

      %{datagouv_id: datagouv_id} =
        insert(:resource,
          url: resource_url,
          dataset: insert(:dataset, is_active: true),
          format: "GTFS",
          title: "title",
          datagouv_id: "1",
          is_community_resource: false
        )

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^resource_url, _headers, options ->
        assert options == [follow_redirect: true]
        {:ok, %HTTPoison.Response{status_code: 500, body: "", headers: []}}
      end)

      assert 0 == count_resource_history()
      assert :ok == perform_job(ResourceHistoryJob, %{datagouv_id: datagouv_id})

      Transport.Test.TestUtils.ensure_no_tmp_files!("resource_")
    end
  end

  defp create_resources_for_history do
    %{id: active_dataset_id} = insert(:dataset, is_active: true)
    %{id: inactive_dataset_id} = insert(:dataset, is_active: false)

    %{datagouv_id: datagouv_id} =
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
      format: "gbfs",
      title: "Ignored because it's not GTFS or NeTEx",
      datagouv_id: "3",
      is_community_resource: false
    )

    insert(:resource,
      url: "https://example.com/gtfs.zip",
      dataset_id: active_dataset_id,
      format: "GTFS",
      title: "Ignored because of duplicated datagouv_id",
      datagouv_id: "4",
      is_community_resource: false
    )

    insert(:resource,
      url: "https://example.com/gtfs.zip",
      dataset_id: active_dataset_id,
      format: "GTFS",
      title: "Ignored because of duplicated datagouv_id",
      datagouv_id: "4",
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

    datagouv_id
  end

  defp zip_metadata do
    [
      %{
        "compressed_size" => 41,
        "file_name" => "ExportService.checksum.md5",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "f0c7216411dec821330ffbebf939bfe73a50707f5e443795a122ec7bef37aa16",
        "uncompressed_size" => 47
      },
      %{
        "compressed_size" => 115,
        "file_name" => "agency.txt",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "548de694a86ab7d6ac0cd3535b0c3b8bffbabcc818e8d7f5a4b8f17030adf617",
        "uncompressed_size" => 143
      },
      %{
        "compressed_size" => 179,
        "file_name" => "calendar.txt",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "390c446ee520bc63c49f69da16d4fe08bceb0511ff19f8491315b739a60f61d6",
        "uncompressed_size" => 495
      },
      %{
        "compressed_size" => 215,
        "file_name" => "calendar_dates.txt",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "4779cd26ddc1d44c8544cb1be449b0f6b48b65fe8344861ee46bcfa3787f9ba7",
        "uncompressed_size" => 1197
      },
      %{
        "compressed_size" => 82,
        "file_name" => "routes.txt",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "27eadc95f783e85c352c9b6b75cc896d9afd236c58c332597a1fac1c14c1f855",
        "uncompressed_size" => 102
      },
      %{
        "compressed_size" => 1038,
        "file_name" => "stop_times.txt",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "dc452a69b86b07841d5de49705ceea22340d639eebfd6589b379d1b38b9b9da1",
        "uncompressed_size" => 5128
      },
      %{
        "compressed_size" => 251,
        "file_name" => "stops.txt",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "2685fb16434b396f277c7ad593b609574ed01592b48de7001c53beb36b926eca",
        "uncompressed_size" => 607
      },
      %{
        "compressed_size" => 71,
        "file_name" => "transfers.txt",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "269d48635624c4b46968cb649fc5a5a1c2224c2dac1670aa6082516ca0c50f59",
        "uncompressed_size" => 102
      },
      %{
        "compressed_size" => 378,
        "file_name" => "trips.txt",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "dd79f0fb8d2fd0a70cc75f49c5f2cae56b9b2ef83670992d6b195e9806393c24",
        "uncompressed_size" => 2864
      }
    ]
  end

  defp count_resource_history do
    DB.Repo.one!(from(r in DB.ResourceHistory, select: count()))
  end

  defp count_resources do
    DB.Repo.one!(from(r in DB.Resource, select: count()))
  end
end
