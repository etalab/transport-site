defmodule Transport.Jobs.GtfsToGeojsonConverterJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox

  alias Transport.Jobs.{GtfsToGeojsonConverterJob, SingleGtfsToGeojsonConverterJob}
  alias Transport.Test.S3TestUtils

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "gtfs to gejson jobs are enqueued" do
    %{id: resource_history_id} =
      insert(:resource_history,
        datagouv_id: "1",
        payload: %{"format" => "GTFS"}
      )

    insert(:resource_history,
      datagouv_id: "2",
      payload: %{"format" => "NeTEx"}
    )

    insert(:resource_history,
      datagouv_id: "3",
      payload: %{}
    )

    # this resource_history should not get enqueued for conversion,
    # as a matching data_conversion already exists
    %{id: not_enqueued_resource_history_id} =
      insert(:resource_history,
        datagouv_id: "4",
        payload: %{"format" => "GTFS", uuid: uuid = Ecto.UUID.generate()}
      )

    # here is the matching data conversion
    insert(:data_conversion, convert_from: "GTFS", convert_to: "GeoJSON", resource_history_uuid: uuid, payload: %{})

    S3TestUtils.s3_mocks_create_bucket()
    :ok = perform_job(GtfsToGeojsonConverterJob, %{})

    assert_enqueued(
      [worker: SingleGtfsToGeojsonConverterJob, args: %{"resource_history_id" => resource_history_id}],
      100
    )

    refute_enqueued(
      [worker: SingleGtfsToGeojsonConverterJob, args: %{"resource_history_id" => not_enqueued_resource_history_id}],
      100
    )
  end
end
