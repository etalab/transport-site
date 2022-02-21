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
        "resource_datagouv_id": resource_datagouv_id
      }
    )
  end
end
