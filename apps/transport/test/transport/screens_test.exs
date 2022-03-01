defmodule Transport.ScreensTest do
  use ExUnit.Case
  import DB.Factory

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "it works" do
    resource_history_uuid = Ecto.UUID.generate()
    resource_datagouv_id = Ecto.UUID.generate()

    %{id: resource_history_id} =
      insert(:resource_history,
        datagouv_id: resource_datagouv_id,
        payload: %{"format" => "GTFS", "uuid" => resource_history_uuid}
      )

    insert(:data_conversion,
      convert_from: "GTFS",
      convert_to: "NeTEx",
      resource_history_uuid: resource_history_uuid,
      payload: %{
        resource_datagouv_id: resource_datagouv_id
      }
    )

    query = """
    SELECT
    resource_history_id,
    resource_datagouv_id,
    CASE WHEN data_conversion_id IS NOT NULL THEN
      TRUE
    ELSE
      FALSE
    END AS conversion_found
    FROM (
    SELECT
      id AS resource_history_id,
      datagouv_id AS resource_datagouv_id,
      payload ->> 'uuid' AS resource_history_uuid
    FROM
      resource_history
    WHERE
      payload ->> 'format' = 'GTFS') resource
    LEFT OUTER JOIN (
    SELECT
      id AS data_conversion_id, convert_from, convert_to, resource_history_uuid
    FROM
      data_conversion
    WHERE
      convert_from = 'GTFS'
      AND convert_to != 'GeoJSON') conversion ON conversion.resource_history_uuid::text = resource.resource_history_uuid

    """

    IO.inspect(Ecto.Adapters.SQL.query(DB.Repo, query), IEx.inspect_opts())
  end
end
