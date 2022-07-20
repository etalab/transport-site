defmodule Transport.Test.Transport.Jobs.GTFSRTEntitiesJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.{GTFSRTEntitiesDispatcherJob, GTFSRTEntitiesJob}
  import ExUnit.CaptureLog

  @url "https://example.com/gtfs-rt"
  @sample_file "#{__DIR__}/../../fixture/files/bibus-brest-gtfs-rt-alerts.pb"

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "GTFSRTEntitiesDispatcherJob" do
    test "selects appropriate resources" do
      active_dataset = insert(:dataset, is_active: true)
      inactive_dataset = insert(:dataset, is_active: false)
      insert(:resource, is_available: true, format: "gbfs")
      insert(:resource, is_available: false, format: "gtfs-rt")
      insert(:resource, is_available: true, format: "gtfs-rt", dataset: inactive_dataset)
      %{id: resource_id} = insert(:resource, is_available: true, format: "gtfs-rt", dataset: active_dataset)

      assert :ok == perform_job(GTFSRTEntitiesDispatcherJob, %{})
      assert [%Oban.Job{args: %{"resource_id" => ^resource_id}}] = all_enqueued(worker: GTFSRTEntitiesJob)
    end
  end

  describe "GTFSRTEntitiesJob" do
    test "days_to_keep" do
      assert 7 == GTFSRTEntitiesJob.days_to_keep()
    end

    test "compute_new_entities with nothing in the database" do
      now = DateTime.utc_now()

      assert %{"trip_updates" => now |> DateTime.to_string(), "service_alerts" => now |> DateTime.to_string()} ==
               GTFSRTEntitiesJob.compute_new_entities(
                 %{},
                 %{trip_updates: 4, vehicle_positions: 0, service_alerts: 1},
                 now
               )
    end

    test "compute_new_entities with things in the database" do
      now = DateTime.utc_now()
      trip_updates_dt = days_ago(now, 4)

      assert %{
               "trip_updates" => trip_updates_dt |> DateTime.to_string(),
               "service_alerts" => now |> DateTime.to_string()
             } ==
               GTFSRTEntitiesJob.compute_new_entities(
                 %{"trip_updates" => trip_updates_dt |> DateTime.to_string()},
                 %{trip_updates: 0, vehicle_positions: 0, service_alerts: 1},
                 now
               )

      assert %{"trip_updates" => now |> DateTime.to_string(), "service_alerts" => now |> DateTime.to_string()} ==
               GTFSRTEntitiesJob.compute_new_entities(
                 %{"trip_updates" => trip_updates_dt |> DateTime.to_string()},
                 %{trip_updates: 5, vehicle_positions: 0, service_alerts: 1},
                 now
               )
    end

    test "removes data over 7 days old" do
      now = DateTime.utc_now()

      assert %{} ==
               GTFSRTEntitiesJob.compute_new_entities(
                 %{"trip_updates" => now |> days_ago(8) |> DateTime.to_string()},
                 %{trip_updates: 0, vehicle_positions: 0, service_alerts: 0},
                 now
               )

      assert %{"vehicle_positions" => now |> DateTime.to_string()} ==
               GTFSRTEntitiesJob.compute_new_entities(
                 %{"trip_updates" => now |> days_ago(8) |> DateTime.to_string()},
                 %{trip_updates: 0, vehicle_positions: 2, service_alerts: 0},
                 now
               )

      dt_trip_updates = now |> days_ago(5)

      assert %{
               "vehicle_positions" => now |> DateTime.to_string(),
               "trip_updates" => dt_trip_updates |> DateTime.to_string()
             } ==
               GTFSRTEntitiesJob.compute_new_entities(
                 %{
                   "trip_updates" => dt_trip_updates |> DateTime.to_string(),
                   "service_alerts" => now |> days_ago(8) |> DateTime.to_string()
                 },
                 %{trip_updates: 0, vehicle_positions: 2, service_alerts: 0},
                 now
               )
    end

    test "perform with nothing in the metadata" do
      setup_gtfs_rt_feed(@url)
      resource = insert(:resource, is_available: true, format: "gtfs-rt", url: @url, datagouv_id: "foo")

      assert :ok == perform_job(GTFSRTEntitiesJob, %{"resource_id" => resource.id})

      assert %{metadata: %{"entities_last_seen" => %{"service_alerts" => _}}, features: ["service_alerts"]} =
               DB.Repo.reload(resource)
    end

    test "perform with stuff in the metadata" do
      setup_gtfs_rt_feed(@url)

      resource =
        insert(:resource,
          is_available: true,
          format: "gtfs-rt",
          url: @url,
          datagouv_id: "foo",
          metadata: %{
            "entities_last_seen" => %{"trip_updates" => DateTime.utc_now() |> days_ago(4) |> DateTime.to_string()},
            "foo" => "bar"
          }
        )

      assert :ok == perform_job(GTFSRTEntitiesJob, %{"resource_id" => resource.id})

      assert %{
               metadata: %{"entities_last_seen" => %{"service_alerts" => _, "trip_updates" => _}, "foo" => "bar"},
               features: ["service_alerts", "trip_updates"]
             } = DB.Repo.reload(resource)
    end

    test "perform with a decode error" do
      setup_http_response(@url, {:ok, %HTTPoison.Response{status_code: 502}})
      resource = insert(:resource, is_available: true, format: "gtfs-rt", url: @url, datagouv_id: "foo")
      {:ok, logs} = with_log(fn -> perform_job(GTFSRTEntitiesJob, %{"resource_id" => resource.id}) end)
      assert %{metadata: nil} = DB.Repo.reload(resource)
      assert logs =~ "Cannot decode GTFS-RT feed"
    end
  end

  defp setup_http_response(url, response) do
    Transport.HTTPoison.Mock |> expect(:get, fn ^url, [], follow_redirect: true -> response end)
  end

  defp setup_gtfs_rt_feed(url) do
    setup_http_response(url, {:ok, %HTTPoison.Response{status_code: 200, body: File.read!(@sample_file)}})
  end

  defp days_ago(dt, days) when days > 0 do
    dt |> DateTime.add(-1 * days * 86_400)
  end
end
