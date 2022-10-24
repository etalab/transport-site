defmodule Transport.Test.Transport.Jobs.GTFSRTEntitiesJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.{GTFSRTEntitiesDispatcherJob, GTFSRTEntitiesJob}
  import ExUnit.CaptureLog

  doctest GTFSRTEntitiesJob, import: true

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

    test "perform with a feed with service_alerts" do
      setup_gtfs_rt_feed(@url)
      resource = insert(:resource, is_available: true, format: "gtfs-rt", url: @url, datagouv_id: "foo")

      assert :ok == perform_job(GTFSRTEntitiesJob, %{"resource_id" => resource.id})

      %{metadata: %{"service_alerts" => _}, features: ["service_alerts"]} =
        DB.ResourceMetadata |> DB.Repo.get_by!(resource_id: resource.id)
    end

    test "perform with a decode error" do
      setup_http_response(@url, {:ok, %HTTPoison.Response{status_code: 502}})
      resource = insert(:resource, is_available: true, format: "gtfs-rt", url: @url, datagouv_id: "foo")
      {:ok, logs} = with_log(fn -> perform_job(GTFSRTEntitiesJob, %{"resource_id" => resource.id}) end)
      assert DB.Repo.aggregate(DB.ResourceMetadata, :count, :id) == 0
      assert logs =~ "Cannot decode GTFS-RT feed"
    end
  end

  defp setup_http_response(url, response) do
    Transport.HTTPoison.Mock |> expect(:get, fn ^url, [], follow_redirect: true -> response end)
  end

  defp setup_gtfs_rt_feed(url) do
    setup_http_response(url, {:ok, %HTTPoison.Response{status_code: 200, body: File.read!(@sample_file)}})
  end
end
