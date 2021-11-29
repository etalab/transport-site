defmodule Transport.Test.Transport.Jobs.ResourceHistoryJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo
  import Mox

  alias Transport.Jobs.{ResourceHistoryDispatcherJob, ResourceHistoryJob}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
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

      %{datagouv_id: datagouv_id} =
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

      assert :ok == perform_job(ResourceHistoryJob, %{datagouv_id: datagouv_id})
    end
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
