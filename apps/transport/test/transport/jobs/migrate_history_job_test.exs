defmodule Transport.Test.Transport.Jobs.MigrateHistoryJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo
  import Ecto.Query
  import Mox
  import Transport.Test.TestUtils

  alias Transport.Jobs.{MigrateHistoryDispatcherJob, MigrateHistoryJob}
  alias Transport.Test.S3TestUtils

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  @gtfs_path "#{__DIR__}/../../../../shared/test/validation/gtfs.zip"
  @gtfs_content File.read!(@gtfs_path)
  @resource_url "https://example.com/Fichiers_GTFS_20201118T000001"

  describe "MigrateHistoryDispatcherJob" do
    test "it works" do
      datagouv_id = "5c34c93f8b4c4104b817fb3a"
      expected_href = "https://dataset-#{datagouv_id}.cellar-c2.services.clever-cloud.com/Fichiers_GTFS_20201118T000001"
      already_backed_up_href = "https://example.com/already_backuped"

      dataset = insert(:dataset, datagouv_id: datagouv_id)
      resource = insert(:resource, datagouv_id: "foo")

      insert(:resource_history,
        payload: %{from_old_system: true, old_href: already_backed_up_href},
        datagouv_id: resource.datagouv_id
      )

      S3TestUtils.s3_mock_list_buckets(["dataset-#{datagouv_id}", "dataset-foo"])

      Transport.History.Fetcher.Mock
      |> expect(:history_resources, fn arg ->
        assert dataset.id == arg.id

        [
          history_payload(dataset, expected_href),
          # Should be ignored because the original URL is on demo-static
          %{href: "", metadata: %{"url" => "https://demo-static.data.gouv.fr/gtfs"}},
          # Should be ignored because it has already been backed up
          %{href: already_backed_up_href, metadata: %{"url" => "https://example.com/file"}}
        ]
      end)

      assert :ok == perform_job(MigrateHistoryDispatcherJob, %{})
      expected_args = dataset |> history_payload(expected_href) |> to_string_keys()
      assert [%Oban.Job{args: ^expected_args}] = all_enqueued(worker: MigrateHistoryJob)
    end
  end

  describe "already_historised?" do
    test "no resources" do
      refute MigrateHistoryJob.already_historised?("https://example.com")
    end

    test "ResourceHistory matching" do
      href = "https://example.com"
      insert(:resource_history, payload: %{from_old_system: true, old_href: href}, datagouv_id: "foo")
      assert MigrateHistoryJob.already_historised?(href)
    end

    test "ResourceHistory not matching" do
      href = "https://example.com"
      insert(:resource_history, payload: %{from_old_system: true, old_href: href}, datagouv_id: "foo")
      refute MigrateHistoryJob.already_historised?(href <> "/foo")
    end
  end

  describe "MigrateHistoryJob" do
    test "it ignores if it has already been backed up" do
      already_backed_up_href = "https://example.com/already_backuped"
      dataset = insert(:dataset)
      resource = insert(:resource, datagouv_id: "foo", dataset: dataset)

      insert(:resource_history,
        payload: %{from_old_system: true, old_href: already_backed_up_href},
        datagouv_id: resource.datagouv_id
      )

      assert :ok == perform_job(MigrateHistoryJob, history_payload(dataset, already_backed_up_href))

      assert 1 == count_resource_history()
    end

    test "not already been backed up but cannot find the resource" do
      assert 0 == count_resource()

      assert :ok ==
               perform_job(MigrateHistoryJob, %{
                 "href" => "https://example.com/href",
                 "dataset_datagouv_id" => "foo",
                 "metadata" => %{"url" => "https://example.com/file"}
               })

      assert 0 == count_resource_history()
    end

    test "a simple successful case" do
      href = "https://cellar.example.com/gtfs.zip"
      gtfs_validator_metadata = %{"foo" => "bar"}
      resource_datagouv_id = "foo"

      dataset = insert(:dataset)

      resource =
        insert(:resource, dataset: dataset, url: @resource_url, datagouv_id: resource_datagouv_id, format: "GTFS")

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^href, _headers, options ->
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

        assert String.starts_with?(path, "#{resource.datagouv_id}/#{resource.datagouv_id}.")
      end)

      Validation.Validator.Mock
      |> expect(:validate_from_url, fn ^href -> {:ok, %{"metadata" => gtfs_validator_metadata}} end)

      assert 0 == count_resource_history()
      assert :ok == perform_job(MigrateHistoryJob, history_payload(dataset, href))
      assert 1 == count_resource_history()

      ensure_no_tmp_files!("resource_")

      expected_zip_metadata = zip_metadata()
      expected_old_payload = dataset |> history_payload(href) |> to_string_keys()

      assert %DB.ResourceHistory{
               datagouv_id: ^resource_datagouv_id,
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
                 "resource_metadata" => ^gtfs_validator_metadata,
                 "total_compressed_size" => 2_370,
                 "total_uncompressed_size" => 10_685,
                 "filename" => filename,
                 "permanent_url" => permanent_url,
                 "zip_metadata" => ^expected_zip_metadata,
                 "uuid" => _uuid,
                 "download_datetime" => _download_datetime,
                 "from_old_system" => true,
                 "old_href" => ^href,
                 "old_payload" => ^expected_old_payload
               },
               last_up_to_date_at: nil
             } = DB.ResourceHistory |> DB.Repo.one!()

      assert permanent_url == Transport.S3.permanent_url(:history, filename)
    end

    test "does not crash when there is a GTFS validator error" do
      href = "https://cellar.example.com/gtfs.zip"
      resource_datagouv_id = "foo"

      dataset = insert(:dataset)

      resource =
        insert(:resource, dataset: dataset, url: @resource_url, datagouv_id: resource_datagouv_id, format: "GTFS")

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^href, _headers, options ->
        assert options == [follow_redirect: true]

        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body: @gtfs_content,
           headers: [{"Content-Type", "application/octet-stream"}, {"x-foo", "bar"}]
         }}
      end)

      Validation.Validator.Mock |> expect(:validate_from_url, fn ^href -> {:error, "500"} end)
      S3TestUtils.s3_mocks_upload_file("#{resource.datagouv_id}/#{resource.datagouv_id}.")

      assert 0 == count_resource_history()
      assert :ok == perform_job(MigrateHistoryJob, history_payload(dataset, href))
      assert 1 == count_resource_history()

      assert %DB.ResourceHistory{
               datagouv_id: ^resource_datagouv_id,
               payload: %{
                 "resource_metadata" => nil,
                 "from_old_system" => true,
                 "old_href" => ^href
               }
             } = DB.ResourceHistory |> DB.Repo.one!()
    end
  end

  defp history_payload(%DB.Dataset{datagouv_id: datagouv_id}, expected_href) do
    %{
      href: expected_href,
      dataset_datagouv_id: datagouv_id,
      is_current: false,
      last_modified: "2020-11-18T00:00:01.953Z",
      metadata: %{
        "content-hash" => "1111dfda713942722c5497f561e9f2f3d4caa23e01f3c26c0a5252b7e7261fcd",
        "end" => "2021-07-04",
        "format" => "GTFS",
        "start" => "2020-11-01",
        "title" => "Fichiers_GTFS",
        "updated-at" => "2020-11-17T10:28:05.852000",
        "url" => @resource_url
      },
      name: "Fichiers_GTFS_20201118T000001"
    }
  end

  defp to_string_keys(map) when is_map(map) do
    map |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)
  end

  defp count_resource_history do
    DB.Repo.one!(from(r in DB.ResourceHistory, select: count()))
  end

  defp count_resource do
    DB.Repo.one!(from(r in DB.Resource, select: count()))
  end
end
