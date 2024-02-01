defmodule Transport.Jobs.GTFSToNeTExConverterJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.DatasetGTFSToNeTExConverterJob
  alias Transport.Jobs.GTFSToNeTExConverterJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "GTFS to NeTEx jobs are enqueued" do
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

    # This resource_history should not get enqueued because a data_conversion already exists
    insert(:resource_history,
      datagouv_id: "4",
      payload: %{"format" => "GTFS", uuid: uuid = Ecto.UUID.generate()}
    )

    insert(:data_conversion,
      convert_from: :GTFS,
      convert_to: :NeTEx,
      converter: "enroute/gtfs-to-netex",
      resource_history_uuid: uuid,
      payload: %{}
    )

    assert :ok = perform_job(GTFSToNeTExConverterJob, %{})

    assert [
             %Oban.Job{
               worker: "Transport.Jobs.GTFSToNeTExEnRouteConverterJob",
               queue: "enroute_conversions",
               args: %{"resource_history_id" => ^resource_history_id, "action" => "create"}
             }
           ] =
             all_enqueued()
  end

  describe "DatasetGTFSToNeTExConverterJob" do
    test "enqueues jobs" do
      dataset = insert(:dataset)
      gtfs_1 = insert(:resource, format: "GTFS", dataset: dataset)
      gtfs_2 = insert(:resource, format: "GTFS", dataset: dataset)
      netex = insert(:resource, format: "NeTEx", dataset: dataset)

      insert(:resource_history, resource: gtfs_1)
      insert(:resource_history, resource: netex)
      %DB.ResourceHistory{id: rh_gtfs_1_id} = insert(:resource_history, resource: gtfs_1)
      %DB.ResourceHistory{id: rh_gtfs_2_id} = insert(:resource_history, resource: gtfs_2)

      assert :ok = perform_job(DatasetGTFSToNeTExConverterJob, %{"dataset_id" => dataset.id})

      # Jobs are enqueued with 2 converters for the latest resource history for
      # each GTFS resource
      assert [
               %Oban.Job{
                 worker: "Transport.Jobs.GTFSToNeTExEnRouteConverterJob",
                 args: %{"action" => "create", "resource_history_id" => ^rh_gtfs_2_id},
                 tags: ["conversions"]
               },
               %Oban.Job{
                 worker: "Transport.Jobs.GTFSToNeTExEnRouteConverterJob",
                 args: %{"action" => "create", "resource_history_id" => ^rh_gtfs_1_id},
                 tags: ["conversions"]
               }
             ] = all_enqueued()
    end
  end
end
