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
