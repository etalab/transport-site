defmodule DB.DataConversionTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  doctest DB.DataConversion, import: true

  test "constraints on data_conversion table" do
    assert %{id: _data_conversion_id} =
             insert(:data_conversion,
               convert_from: :GTFS,
               convert_to: :GeoJSON,
               resource_history_uuid: Ecto.UUID.generate(),
               payload: %{}
             )

    # Enforce correct case for convert_from format
    # Constraints are enforced by the DB and by `Ecto.Enum`s
    assert_raise(RuntimeError, fn ->
      insert(:data_conversion,
        convert_from: "gtfsqq",
        convert_to: "GeoJSON",
        resource_history_uuid: Ecto.UUID.generate(),
        payload: %{}
      )
    end)

    # enforce correct case for convert_to format
    assert_raise(RuntimeError, fn ->
      insert(:data_conversion,
        convert_from: :GTFS,
        convert_to: :geojson,
        resource_history_uuid: Ecto.UUID.generate(),
        payload: %{}
      )
    end)
  end

  test "uniqueness of data_conversion" do
    assert %{id: _data_conversion_id} =
             insert(:data_conversion,
               convert_from: :GTFS,
               convert_to: :GeoJSON,
               resource_history_uuid: uuid = Ecto.UUID.generate(),
               payload: %{}
             )

    # you cannot have 2 rows with the same {convert_from, convert_to, resource_history_uuid}
    assert_raise(Ecto.ConstraintError, fn ->
      insert(:data_conversion,
        convert_from: :GTFS,
        convert_to: :GeoJSON,
        resource_history_uuid: uuid,
        payload: %{}
      )
    end)
  end

  test "list data conversions of a dataset" do
    dataset = insert(:dataset)
    resource_1 = insert(:resource, dataset_id: dataset.id, format: "GTFS")

    # not listed as there is more recent
    insert(:resource_history,
      resource_id: resource_1.id,
      payload: %{uuid: uuid_old = Ecto.UUID.generate(), inserted_at: DateTime.utc_now() |> DateTime.add(-1, :day)}
    )

    insert(:data_conversion,
      convert_from: "GTFS",
      convert_to: "GeoJSON",
      converter: DB.DataConversion.converter_to_use("GeoJSON"),
      resource_history_uuid: uuid_old,
      payload: %{filename: "filename_old"}
    )

    # listed
    resource_history_1 =
      insert(:resource_history, resource_id: resource_1.id, payload: %{uuid: uuid = Ecto.UUID.generate()})

    data_conversion =
      insert(:data_conversion,
        convert_from: "GTFS",
        convert_to: "GeoJSON",
        converter: DB.DataConversion.converter_to_use("GeoJSON"),
        resource_history_uuid: uuid,
        payload: %{filename: "filename"}
      )

    # listed (other resource same dataset)
    resource_2 = insert(:resource, dataset_id: dataset.id, format: "GTFS")

    resource_history_2 =
      insert(:resource_history, resource_id: resource_2.id, payload: %{uuid: uuid_2 = Ecto.UUID.generate()})

    data_conversion_2 =
      insert(:data_conversion,
        convert_from: "GTFS",
        convert_to: "GeoJSON",
        converter: DB.DataConversion.converter_to_use("GeoJSON"),
        resource_history_uuid: uuid_2,
        payload: %{filename: "filename_2"}
      )

    # not listed, other dataset
    dataset_other = insert(:dataset)
    resource_other = insert(:resource, dataset_id: dataset_other.id)

    _resource_history_other =
      insert(:resource_history, resource_id: resource_other.id, payload: %{uuid: uuid_other = Ecto.UUID.generate()})

    _data_conversion_other =
      insert(:data_conversion,
        convert_from: "GTFS",
        convert_to: "GeoJSON",
        converter: DB.DataConversion.converter_to_use("GeoJSON"),
        resource_history_uuid: uuid_other,
        payload: %{filename: "filename"}
      )

    _ignored_non_default_converter =
      insert(:data_conversion,
        convert_from: "GTFS",
        convert_to: "GeoJSON",
        converter: "non-default-geojson-converter",
        resource_history_uuid: uuid_other,
        payload: %{filename: "filename"}
      )

    conversions =
      dataset.id
      |> DB.DataConversion.latest_data_conversions("GeoJSON")
      |> Enum.sort_by(fn %{data_conversion_id: dc_id} -> dc_id end, :asc)

    assert [
             %{
               data_conversion_id: data_conversion.id,
               resource_history_id: resource_history_1.id,
               s3_path: "filename"
             },
             %{
               data_conversion_id: data_conversion_2.id,
               resource_history_id: resource_history_2.id,
               s3_path: "filename_2"
             }
           ] == conversions
  end
end
