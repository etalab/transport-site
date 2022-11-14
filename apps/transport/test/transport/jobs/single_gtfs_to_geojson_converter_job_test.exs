defmodule Transport.Jobs.SingleGtfsToGeojsonConverterJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.SingleGtfsToGeojsonConverterJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "a non GTFS resource" do
    %{id: resource_history_id} =
      insert(:resource_history,
        payload: %{"format" => "NeTEx"}
      )

    # no mox expectation set, and the test passes => conversion is properly skipped
    assert {:discard, "Conversion is not needed"} ==
             perform_job(SingleGtfsToGeojsonConverterJob, %{"resource_history_id" => resource_history_id})
  end

  test "existing conversion" do
    uuid = Ecto.UUID.generate()
    insert(:data_conversion, convert_from: "GTFS", convert_to: "GeoJSON", resource_history_uuid: uuid, payload: %{})

    %{id: resource_history_id} = insert(:resource_history, payload: %{"uuid" => uuid, "format" => "GTFS"})

    # no mox expectation set, and the test passes => conversion is properly skipped
    assert {:discard, "Conversion is not needed"} ==
             perform_job(SingleGtfsToGeojsonConverterJob, %{"resource_history_id" => resource_history_id})
  end

  test "launch a conversion" do
    permanent_url = "https://resource.fr"
    uuid = Ecto.UUID.generate()

    # add a resource history
    %{id: resource_history_id} =
      insert(:resource_history,
        payload: %{"uuid" => uuid, "format" => "GTFS", "permanent_url" => permanent_url, "filename" => "fff"}
      )

    # mock for the resource download
    Transport.HTTPoison.Mock
    |> expect(:get!, 1, fn ^permanent_url ->
      %{status_code: 200, body: "this is my GTFS file"}
    end)

    # mock for the resource conversion
    Transport.Rambo.Mock
    |> expect(:run, 1, fn _binary_path, ["--input", _file_path, "--output", geojson_file_path], _opts ->
      File.write!(geojson_file_path, "this my geojson content")
      {:ok, "this my geojson content"}
    end)

    Transport.Test.S3TestUtils.s3_mocks_upload_file("conversions/gtfs-to-geojson/")

    # job succeed
    assert :ok ==
             perform_job(SingleGtfsToGeojsonConverterJob, %{"resource_history_id" => resource_history_id})

    # a data_conversion row is recorded ✌️‍
    DB.DataConversion
    |> DB.Repo.get_by!(
      convert_from: "GTFS",
      convert_to: "GeoJSON",
      resource_history_uuid: uuid
    )

    Transport.Test.TestUtils.ensure_no_tmp_files!("conversion_gtfs_geojson_")
  end

  test "a failing GeoJSON conversion" do
    permanent_url = "https://resource.fr"
    uuid = Ecto.UUID.generate()

    # add a resource history
    %{id: resource_history_id} =
      resource_history =
      insert(:resource_history,
        payload: %{"uuid" => uuid, "format" => "GTFS", "permanent_url" => permanent_url, "filename" => "fff"}
      )

    # mock for the resource download
    Transport.HTTPoison.Mock
    |> expect(:get!, 1, fn ^permanent_url ->
      %{status_code: 200, body: "this is my GTFS file"}
    end)

    # mock for the failing conversion
    Transport.Rambo.Mock
    |> expect(:run, 1, fn _binary_path, ["--input", _file_path, "--output", _geojson_file_path], _opts ->
      {:error, "conversion failed"}
    end)

    assert {:discard, _} = perform_job(SingleGtfsToGeojsonConverterJob, %{"resource_history_id" => resource_history_id})

    # ResourceHistory's payload is updated with the error information
    expected_payload =
      Map.merge(resource_history.payload, %{
        "conversion_GeoJSON_error" => "conversion failed",
        "conversion_GeoJSON_fatal_error" => true
      })

    assert %DB.ResourceHistory{payload: ^expected_payload} = DB.Repo.reload!(resource_history)

    # no data_conversion row is recorded
    assert_raise(Ecto.NoResultsError, fn ->
      DB.DataConversion
      |> DB.Repo.get_by!(
        convert_from: "GTFS",
        convert_to: "GeoJSON",
        resource_history_uuid: uuid
      )
    end)

    # all temp files have been cleaned
    Transport.Test.TestUtils.ensure_no_tmp_files!("conversion_gtfs_geojson_")
  end
end
