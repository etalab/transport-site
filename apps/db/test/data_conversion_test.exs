defmodule DB.DataConversionTest do
  use ExUnit.Case, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "constraints on data_conversion table" do
    assert %{id: data_conversion_id} =
             insert(:data_conversion,
               convert_from: "GTFS",
               convert_to: "GeoJSON",
               resource_history_uuid: Ecto.UUID.generate(),
               payload: %{}
             )

    # Enforce correct case for convert_from format
    # Constraints are enforced by the DB, if we need to support new formats,
    # we need to do via a new migration.
    assert_raise(Ecto.ConstraintError, fn ->
      insert(:data_conversion,
        convert_from: "gtfsqq",
        convert_to: "GeoJSON",
        resource_history_uuid: Ecto.UUID.generate(),
        payload: %{}
      )
    end)

    # enforce correct case for convert_to format
    assert_raise(Ecto.ConstraintError, fn ->
      insert(:data_conversion,
        convert_from: "GTFS",
        convert_to: "geojson",
        resource_history_uuid: Ecto.UUID.generate(),
        payload: %{}
      )
    end)
  end

  test "uniqueness of data_conversion" do
    assert %{id: data_conversion_id} =
             insert(:data_conversion,
               convert_from: "GTFS",
               convert_to: "GeoJSON",
               resource_history_uuid: uuid = Ecto.UUID.generate(),
               payload: %{}
             )

    # you cannot have 2 rows with the same {convert_from, convert_to, resource_history_uuid}
    assert_raise(Ecto.ConstraintError, fn ->
      insert(:data_conversion,
        convert_from: "GTFS",
        convert_to: "GeoJSON",
        resource_history_uuid: uuid,
        payload: %{}
      )
    end)
  end
end
