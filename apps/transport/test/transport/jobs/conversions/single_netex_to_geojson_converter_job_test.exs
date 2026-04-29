defmodule Transport.Jobs.SingleNeTExToGeoJSONConverterJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import ExUnit.CaptureLog
  import Mox
  alias Transport.Jobs.SingleNeTExToGeoJSONConverterJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "a non NeTEx resource" do
    %{id: resource_history_id} =
      insert(:resource_history,
        payload: %{"format" => "GTFS"}
      )

    # no mox expectation set, and the test passes => conversion is properly skipped
    assert {:cancel, "Conversion is not needed"} ==
             perform_job(SingleNeTExToGeoJSONConverterJob, %{"resource_history_id" => resource_history_id})
  end

  test "existing conversion" do
    uuid = Ecto.UUID.generate()

    insert(:data_conversion,
      convert_from: :NeTEx,
      convert_to: :GeoJSON,
      resource_history_uuid: uuid,
      converter: DB.DataConversion.converter_to_use(:NeTEx, :GeoJSON),
      payload: %{}
    )

    %{id: resource_history_id} = insert(:resource_history, payload: %{"uuid" => uuid, "format" => "NeTEx"})

    # no mox expectation set, and the test passes => conversion is properly skipped
    assert {:cancel, "Conversion is not needed"} ==
             perform_job(SingleNeTExToGeoJSONConverterJob, %{"resource_history_id" => resource_history_id})
  end

  test "launch a conversion" do
    permanent_url = "https://resource.fr"
    uuid = Ecto.UUID.generate()

    # add a resource history
    %{id: resource_history_id} =
      insert(:resource_history,
        payload: %{"uuid" => uuid, "format" => "NeTEx", "permanent_url" => permanent_url, "filename" => "fff"}
      )

    ZipCreator.with_tmp_zip([{"data.xml", "this is my NeTEx file"}], fn zip_file ->
      {:ok, zip_content} = File.read(zip_file)

      # mock for the resource download
      Transport.HTTPoison.Mock
      |> expect(:get!, 1, fn ^permanent_url ->
        %{status_code: 200, body: zip_content}
      end)

      Transport.Test.S3TestUtils.s3_mock_stream_file(
        start_path: "conversions/netex-to-geojson/",
        bucket: "transport-data-gouv-fr-resource-history-test"
      )

      # job succeed
      assert :ok ==
               perform_job(SingleNeTExToGeoJSONConverterJob, %{"resource_history_id" => resource_history_id})

      # a data_conversion row is recorded ✌️‍
      assert %DB.DataConversion{payload: %{"filesize" => 42, "filename" => "conversions/netex-to-geojson/fff.geojson"}} =
               DB.Repo.get_by!(DB.DataConversion,
                 convert_from: :NeTEx,
                 convert_to: :GeoJSON,
                 converter: DB.DataConversion.converter_to_use(:NeTEx, :GeoJSON),
                 resource_history_uuid: uuid
               )

      Transport.Test.TestUtils.ensure_no_tmp_files!("conversion_netex_geojson_")
    end)
  end

  test "a failing GeoJSON conversion" do
    permanent_url = "https://resource.fr"
    uuid = Ecto.UUID.generate()

    # add a resource history
    %{id: resource_history_id} =
      resource_history =
      insert(:resource_history,
        payload: %{"uuid" => uuid, "format" => "NeTEx", "permanent_url" => permanent_url, "filename" => "fff"}
      )

    # mock for the resource download
    Transport.HTTPoison.Mock
    |> expect(:get!, 1, fn ^permanent_url ->
      %{status_code: 200, body: "obviously invalid zip file"}
    end)

    logs =
      capture_log([level: :error], fn ->
        assert {:cancel, _} =
                 perform_job(SingleNeTExToGeoJSONConverterJob, %{"resource_history_id" => resource_history_id})

        # ResourceHistory's payload is updated with the error information
        expected_payload =
          Map.merge(resource_history.payload, %{
            "conversion_GeoJSON_error" => "Invalid zip file, missing EOCD record",
            "conversion_GeoJSON_fatal_error" => true
          })

        assert %DB.ResourceHistory{payload: ^expected_payload} = DB.Repo.reload!(resource_history)

        # no data_conversion row is recorded
        assert_raise(Ecto.NoResultsError, fn ->
          DB.DataConversion
          |> DB.Repo.get_by!(
            convert_from: :NeTEx,
            convert_to: :GeoJSON,
            converter: DB.DataConversion.converter_to_use(:NeTEx, :GeoJSON),
            resource_history_uuid: uuid
          )
        end)

        # all temp files have been cleaned
        Transport.Test.TestUtils.ensure_no_tmp_files!("conversion_netex_geojson_")
      end)

    assert logs =~ "Invalid zip file"
  end
end
