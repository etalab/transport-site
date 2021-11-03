defmodule Transport.HistoryTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "backup_resources" do
    insert(:resource,
      url: resource_url = "http://localhost/the-resource-url",
      title: "Hello",
      format: "GTFS",
      is_community_resource: false,
      dataset: insert(:dataset),
      # See https://github.com/etalab/transport-site/issues/1550
      # to understand why this has got a weird format
      last_update:
        DateTime.utc_now()
        |> DateTime.add(-5 * 60 * 60 * 24, :second)
        |> DateTime.to_iso8601()
        |> String.replace(" ", "T"),
      last_import: DateTime.utc_now() |> DateTime.add(-6 * 60 * 60, :second) |> DateTime.to_iso8601(),
      content_hash: "fake_content_hash"
    )

    Transport.HTTPoison.Mock
    |> expect(:get, fn url ->
      assert url == resource_url
      {:ok, %{status_code: 200, body: "the-payload"}}
    end)

    Transport.ExAWS.Mock
    # bucket creation
    |> expect(:request!, fn request ->
      assert %{
               service: :s3,
               http_method: :put,
               path: "/",
               bucket: "dataset-123",
               headers: %{"x-amz-acl" => "public-read"}
             } = request
    end)
    |> expect(:stream!, fn request ->
      assert %{
               service: :s3,
               bucket: "dataset-123",
               http_method: :get,
               params: %{"prefix" => "Hello"},
               path: "/"
             } = request

      [%{key: "hello", owner: %{display_name: "foo@fake-cellar_organisation_id"}}]
    end)
    |> expect(:request!, fn request ->
      assert %{
               service: :s3,
               bucket: "dataset-123",
               http_method: :head,
               path: "hello"
             } = request

      %{
        headers: %{
          "x-amz-meta-content-hash" => "some-hash",
          # The S3 API returns a string and not a DateTime
          "x-amz-meta-updated-at" => DateTime.utc_now() |> DateTime.add(-60 * 60 * 24, :second) |> DateTime.to_string()
        }
      }
    end)
    |> expect(:request!, fn request ->
      # Check meta headers do not contain underscores
      # S3 metadata keys are usually transformed (_ are turned into -)
      %{headers: headers} = request

      meta_headers_with_underscores = :maps.filter(fn k, _ -> String.match?(k, ~r/^x-amz-meta-\S*_\S*$/) end, headers)

      :maps.map(
        fn k, _ -> raise ArgumentError, "`#{k}` header should not contain underscores" end,
        meta_headers_with_underscores
      )

      assert %{
               service: :s3,
               bucket: "dataset-123",
               headers: %{"x-amz-acl" => "public-read", "x-amz-meta-content-hash" => "fake_content_hash"},
               http_method: :put,
               body: "the-payload"
             } = request
    end)

    assert :ok == Transport.History.Backup.backup_resources()
  end

  describe "Fetcher.S3" do
    test "history_resources (regular use)" do
      dataset = :dataset |> insert() |> DB.Repo.preload(:resources)

      Transport.ExAWS.Mock
      |> expect(:stream!, fn request ->
        assert %{
                 service: :s3,
                 bucket: "dataset-123",
                 http_method: :get,
                 path: "/"
               } = request

        [
          %{
            key: "some-resource",
            last_modified: DateTime.add(DateTime.utc_now(), -60 * 60 * 24, :second),
            owner: %{display_name: "foo@fake-cellar_organisation_id"}
          },
          # Resource *not* belonging to our organisation
          %{
            key: "other-resource",
            last_modified: DateTime.add(DateTime.utc_now(), -60 * 60 * 24, :second),
            owner: %{display_name: "foo@other-cellar_organisation_id"}
          }
        ]
      end)
      |> expect(:request!, fn request ->
        assert %{
                 service: :s3,
                 bucket: "dataset-123",
                 path: "some-resource",
                 http_method: :head
               } = request

        %{headers: %{}}
      end)

      resources = Transport.History.Fetcher.S3.history_resources(dataset)

      assert [
               %{
                 name: "some-resource",
                 href: "https://dataset-123.cellar-c2.services.clever-cloud.com/some-resource"
               }
             ] = resources
    end
  end
end
