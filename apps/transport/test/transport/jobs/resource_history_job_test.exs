defmodule Transport.Test.Transport.Jobs.ResourceHistoryJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo
  import Ecto.Query
  import Mox

  alias Transport.Jobs.{ResourceHistoryDispatcherJob, ResourceHistoryJob}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    DB.Repo.delete_all(DB.ResourceHistory)
    :ok
  end

  setup :verify_on_exit!

  @gtfs_path "#{__DIR__}/../../../../shared/test/validation/gtfs.zip"
  @gtfs_content File.read!(@gtfs_path)

  describe "ResourceHistoryDispatcherJob" do
    test "a simple successful case" do
      s3_mocks_create_bucket()

      %{datagouv_id: datagouv_id} =
        insert(:resource,
          url: "https://example.com/gtfs.zip",
          format: "GTFS",
          title: "title",
          datagouv_id: "1",
          is_community_resource: false
        )

      # Resources that should be ignored
      insert(:resource,
        url: "https://example.com/gtfs.zip",
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
        format: "GTFS",
        title: "Ignored because of duplicated datagouv_id",
        datagouv_id: "4",
        is_community_resource: false
      )

      insert(:resource,
        url: "https://example.com/gtfs.zip",
        format: "GTFS",
        title: "Ignored because of duplicated datagouv_id",
        datagouv_id: "4",
        is_community_resource: false
      )

      assert :ok == perform_job(ResourceHistoryDispatcherJob, %{})
      assert [%{args: %{"datagouv_id" => ^datagouv_id}}] = all_enqueued(worker: ResourceHistoryJob)
      refute_enqueued(worker: ResourceHistoryDispatcherJob)
    end
  end

  describe "ResourceHistoryJob" do
    test "a simple successful case" do
      resource_url = "https://example.com/gtfs.zip"

      %{datagouv_id: datagouv_id, metadata: resource_metadata} =
        insert(:resource,
          url: resource_url,
          format: "GTFS",
          title: "title",
          datagouv_id: "1",
          is_community_resource: false,
          metadata: %{"foo" => "bar"}
        )

      Unlock.HTTP.Client.Mock
      |> expect(:get!, fn url, _headers ->
        assert url == resource_url
        %{status: 200, body: @gtfs_content, headers: [{"content-type", "application/octet-stream"}, {"x-foo", "bar"}]}
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

      ensure_no_tmp_files!()

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
                 "upload_filename" => _upload_filename,
                 "zip_metadata" => [
                   %{
                     "compressed_size" => 41,
                     "file_name" => "ExportService.checksum.md5",
                     "last_modified_datetime" => "2017-02-16T05:01:12",
                     "uncompressed_size" => 47
                   },
                   %{
                     "compressed_size" => 115,
                     "file_name" => "agency.txt",
                     "last_modified_datetime" => "2017-02-16T05:01:12",
                     "uncompressed_size" => 143
                   },
                   %{
                     "compressed_size" => 179,
                     "file_name" => "calendar.txt",
                     "last_modified_datetime" => "2017-02-16T05:01:12",
                     "uncompressed_size" => 495
                   },
                   %{
                     "compressed_size" => 215,
                     "file_name" => "calendar_dates.txt",
                     "last_modified_datetime" => "2017-02-16T05:01:12",
                     "uncompressed_size" => 1197
                   },
                   %{
                     "compressed_size" => 82,
                     "file_name" => "routes.txt",
                     "last_modified_datetime" => "2017-02-16T05:01:12",
                     "uncompressed_size" => 102
                   },
                   %{
                     "compressed_size" => 1038,
                     "file_name" => "stop_times.txt",
                     "last_modified_datetime" => "2017-02-16T05:01:12",
                     "uncompressed_size" => 5128
                   },
                   %{
                     "compressed_size" => 251,
                     "file_name" => "stops.txt",
                     "last_modified_datetime" => "2017-02-16T05:01:12",
                     "uncompressed_size" => 607
                   },
                   %{
                     "compressed_size" => 71,
                     "file_name" => "transfers.txt",
                     "last_modified_datetime" => "2017-02-16T05:01:12",
                     "uncompressed_size" => 102
                   },
                   %{
                     "compressed_size" => 378,
                     "file_name" => "trips.txt",
                     "last_modified_datetime" => "2017-02-16T05:01:12",
                     "uncompressed_size" => 2864
                   }
                 ]
               },
               version: 1
             } = DB.ResourceHistory |> DB.Repo.one!()
    end
  end

  defp ensure_no_tmp_files! do
    tmp_files = System.tmp_dir!() |> File.ls!()
    assert tmp_files |> Enum.filter(fn f -> String.starts_with?(f, "resource_") end) |> Enum.empty?()
  end

  defp count_resource_history do
    DB.Repo.one!(from(r in DB.ResourceHistory, select: count()))
  end

  defp s3_mocks_create_bucket do
    Transport.ExAWS.Mock
    # Listing buckets
    |> expect(:request!, fn request ->
      assert %{
               service: :s3,
               http_method: :get,
               path: "/"
             } = request

      %{body: %{buckets: []}}
    end)

    Transport.ExAWS.Mock
    # Bucket creation
    |> expect(:request!, fn request ->
      bucket_name = Transport.S3.bucket_name(:history)

      assert %{
               service: :s3,
               http_method: :put,
               path: "/",
               bucket: ^bucket_name,
               headers: %{"x-amz-acl" => "public-read"}
             } = request
    end)
  end
end
