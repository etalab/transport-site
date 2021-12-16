defmodule Transport.Jobs.SingleGtfsToGeojsonConverterJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "a non GTFS resource" do
    %{id: resource_history_id} =
      insert(:resource_history,
        datagouv_id: "2",
        payload: %{"format" => "NeTEx"}
      )

    # no mox expectation set, and the test passes => conversion is properly skipped
    assert :ok ==
             Transport.Jobs.SingleGtfsToGeojsonConverterJob.perform(%{
               args: %{"resource_history_id" => resource_history_id}
             })
  end

  test "existing conversion" do
    uuid = "some-uuid"
    insert(:data_conversion, convert_from: "GTFS", convert_to: "GeoJSON", resource_history_uuid: uuid, payload: %{})

    %{id: resource_history_id} =
      insert(:resource_history,
        datagouv_id: "2",
        payload: %{"uuid" => uuid, "format" => "GTFS", "permanent_url" => "xxx", "filename" => "fff"}
      )

    # no mox expectation set, and the test passes => conversion is properly skipped
    assert :ok ==
             Transport.Jobs.SingleGtfsToGeojsonConverterJob.perform(%{
               args: %{"resource_history_id" => resource_history_id}
             })
  end

  test "launch a conversion" do
    permanent_url = "https://resource.fr"
    uuid = "some-nice-uuid"

    # add a resource history
    %{id: resource_history_id} =
      insert(:resource_history,
        datagouv_id: "2",
        payload: %{"uuid" => uuid, "format" => "GTFS", "permanent_url" => permanent_url, "filename" => "fff"}
      )

    # mock for the resource download
    Transport.HTTPoison.Mock
    |> expect(:get!, 1, fn ^permanent_url, [], [follow_redirect: true] ->
      %{status_code: 200, body: "this is my GTFS file"}
    end)

    # mock for the resource conversion
    Transport.Rambo.Mock
    |> expect(:run, 1, fn _binary_path, opts ->
      assert(["--input", _file_path, "--output", geojson_file_path] = opts)
      File.write!(geojson_file_path, "this my geojson content")
      {:ok, "this my geojson content"}
    end)

    # mock for the aws upload
    Transport.ExAWS.Mock
    |> expect(:request!, fn %{
                              service: :s3,
                              http_method: :put,
                              path: path,
                              bucket: _bucket_name,
                              body: _content,
                              headers: %{"x-amz-acl" => "public-read"}
                            } ->
      assert path |> String.starts_with?("conversions/gtfs-to-geojson/")
    end)

    # job succeed
    assert :ok ==
             Transport.Jobs.SingleGtfsToGeojsonConverterJob.perform(%{
               args: %{"resource_history_id" => resource_history_id}
             })

    # a data_conversion row is recorded ✌️‍
    DB.DataConversion
    |> DB.Repo.get_by!(
      convert_from: "GTFS",
      convert_to: "GeoJSON",
      resource_history_uuid: uuid
    )
  end
end
