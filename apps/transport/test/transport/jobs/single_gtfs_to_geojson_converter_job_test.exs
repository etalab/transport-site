defmodule Transport.Jobs.SingleGtfsToGeojsonConverterJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  # alias Transport.Jobs.{GtfsToGeojsonConverterJob, ResourceHistoryJob, SingleGtfsToGeojsonConverterJob}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    # DB.Repo.delete_all(DB.ResourceHistory)
    :ok
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
end
