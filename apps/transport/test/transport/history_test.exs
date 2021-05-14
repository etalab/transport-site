defmodule Transport.HistoryTest do
  use ExUnit.Case, async: true
  import TransportWeb.Factory
  import Mox

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  @tag :focus
  test "backup_resources" do
    insert(:resource,
      url: resource_url = "http://localhost/the-resource-url",
      title: "Hello",
      format: "GTFS",
      is_community_resource: false,
      dataset: insert(:dataset),
      last_update: DateTime.utc_now() |> DateTime.to_iso8601()
    )

    Transport.HTTPoison.Mock
    |> expect(:get, fn resource_url ->
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

      [%{key: "hello"}]
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
          "content-hash" => "some-hash",
          "updated_at" => DateTime.add(DateTime.utc_now(), -60 * 60 * 24, :second)
        }
      }
    end)
    |> expect(:request!, fn request ->
      assert %{
               service: :s3,
               bucket: "dataset-123",
               headers: %{"x-amz-acl" => "public-read"},
               http_method: :put,
               body: "the-payload"
             } = request
    end)

    assert :ok == Transport.History.Backup.backup_resources()
  end

  test "history_resources" do
    dataset = insert(:dataset)

    # TODO: support "no bucket found" error by returning an empty thing,
    # otherwise raise
    Transport.History.Fetcher.history_resources(dataset)
  end
end
