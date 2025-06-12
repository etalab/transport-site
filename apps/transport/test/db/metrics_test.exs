defmodule DB.MetricsTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Transport.Telemetry, only: [truncate_datetime_to_hour: 1]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)

    today = truncate_datetime_to_hour(DateTime.utc_now())
    yesterday = truncate_datetime_to_hour(DateTime.add(DateTime.utc_now(), -1 * 24 * 60 * 60, :second))

    DB.Repo.delete_all(DB.Metrics)
    insert(:metrics, target: "foo", event: "internal", count: 5, period: yesterday)
    insert(:metrics, target: "foo", event: "internal", count: 3, period: today)
    insert(:metrics, target: "foo", event: "external", count: 3, period: today)
    insert(:metrics, target: "bar", event: "external", count: 2, period: today)

    :ok
  end

  test "requests_over_last_days" do
    today = truncate_datetime_to_hour(DateTime.utc_now())
    yesterday = truncate_datetime_to_hour(DateTime.add(DateTime.utc_now(), -1, :day))

    gtfs_rt_resource =
      insert(:resource,
        format: "gtfs-rt",
        url: "https://proxy.transport.data.gouv.fr/resource/divia-dijon-gtfs-rt-trip-update"
      )

    insert(:metrics,
      target: "proxy:divia-dijon-gtfs-rt-trip-update",
      event: "proxy:request:external",
      count: 2,
      period: today
    )

    insert(:metrics,
      target: "proxy:divia-dijon-gtfs-rt-trip-update",
      event: "proxy:request:internal",
      count: 1,
      period: today
    )

    insert(:metrics,
      target: "proxy:divia-dijon-gtfs-rt-trip-update",
      event: "proxy:request:external",
      count: 3,
      period: yesterday
    )

    insert(:metrics,
      target: "proxy:divia-dijon-gtfs-rt-trip-update",
      event: "proxy:request:internal",
      count: 1,
      period: yesterday
    )

    assert [
             %{date: Date.utc_today() |> Date.add(-1), requests_external: 3, requests_internal: 1},
             %{date: Date.utc_today(), requests_external: 2, requests_internal: 1}
           ] ==
             DB.Metrics.requests_over_last_days(gtfs_rt_resource, 2)
  end

  describe "for_last_days" do
    test "it works" do
      assert %{"bar" => %{"external" => 2}, "foo" => %{"external" => 3, "internal" => 8}} == DB.Metrics.for_last_days(2)
      assert %{"bar" => %{"external" => 2}, "foo" => %{"external" => 3, "internal" => 3}} == DB.Metrics.for_last_days(1)
    end

    test "it can filter by events" do
      assert %{} == DB.Metrics.for_last_days(3, ["nope"])
      assert %{"foo" => %{"internal" => 8}} == DB.Metrics.for_last_days(2, ["internal"])
      assert %{"foo" => %{"internal" => 3}} == DB.Metrics.for_last_days(1, ["internal"])
    end

    test "does not handle negative days" do
      assert_raise FunctionClauseError, fn -> DB.Metrics.for_last_days(-1) end
    end
  end
end
