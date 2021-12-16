defmodule Transport.Jobs.GtfsToGeojsonConverterJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory

  alias Transport.Jobs.{GtfsToGeojsonConverterJob, ResourceHistoryJob, SingleGtfsToGeojsonConverterJob}
  alias Transport.Test.S3TestUtils

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  # setup :verify_on_exit!
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

    S3TestUtils.s3_mocks_create_bucket()
    :ok = GtfsToGeojsonConverterJob.perform(%{})

    assert_enqueued(
      [worker: SingleGtfsToGeojsonConverterJob, args: %{"resource_history_id" => resource_history_id}],
      100
    )
  end
end
