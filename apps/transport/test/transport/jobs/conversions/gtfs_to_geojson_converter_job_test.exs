defmodule Transport.Jobs.GTFSToGeoJSONConverterJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.GTFSToGeoJSONConverterJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "GTFS to GeoJSON jobs are enqueued" do
    %{id: resource_history_id} =
      insert(:resource_history,
        datagouv_id: "1",
        payload: %{"format" => "GTFS", "uuid" => Ecto.UUID.generate()}
      )

    insert(:resource_history,
      datagouv_id: "2",
      payload: %{"format" => "NeTEx", "uuid" => Ecto.UUID.generate()}
    )

    insert(:resource_history, datagouv_id: "3", payload: %{})

    # Ignored because it previously had a fatal conversion error
    insert(:resource_history,
      datagouv_id: "4",
      payload: %{"format" => "GTFS", "uuid" => Ecto.UUID.generate(), "conversion_GeoJSON_fatal_error" => true}
    )

    # This resource_history should not get enqueued for conversion,
    # as a matching data_conversion already exists
    insert(:resource_history,
      datagouv_id: "4",
      payload: %{"format" => "GTFS", uuid: uuid = Ecto.UUID.generate()}
    )

    insert(:data_conversion,
      convert_from: :GTFS,
      convert_to: :GeoJSON,
      converter: DB.DataConversion.converter_to_use(:GeoJSON),
      resource_history_uuid: uuid,
      payload: %{}
    )

    assert :ok = perform_job(GTFSToGeoJSONConverterJob, %{})

    assert [%Oban.Job{args: %{"resource_history_id" => ^resource_history_id}}] =
             all_enqueued()
  end
end
