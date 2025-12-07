defmodule Unlock.BatchMetricsTest do
  use ExUnit.Case, async: true
  import DB.Factory

  doctest Unlock.BatchMetrics, import: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    pid = Process.whereis(Unlock.BatchMetrics)
    Ecto.Adapters.SQL.Sandbox.allow(DB.Repo, self(), pid)
    :ok
  end

  test "work delay is less than cache expiration" do
    assert Unlock.BatchMetrics.work_delay() / 1_000 < Unlock.Shared.default_cache_expiration_seconds()
  end

  test "work" do
    period = DateTime.utc_now() |> Unlock.BatchMetrics.truncate_datetime_to_hour()
    insert(:metrics, %{target: "bar", event: "internal", period: period, count: 1})

    Unlock.BatchMetrics.incr_event(%{target: "foo", event: "external"})
    Unlock.BatchMetrics.incr_event(%{target: "foo", event: "external"})
    Unlock.BatchMetrics.incr_event(%{target: "foo", event: "external"})
    Unlock.BatchMetrics.incr_event(%{target: "bar", event: "internal"})

    assert %{"external@foo" => 3, "internal@bar" => 1} == :sys.get_state(Unlock.BatchMetrics)

    send(Unlock.BatchMetrics, :work)
    :timer.sleep(100)

    assert [
             # Metric has been updated
             %DB.Metrics{
               count: 2,
               period: ^period,
               target: "bar",
               event: "internal"
             },
             # New metric has been inserted
             %DB.Metrics{
               count: 3,
               period: ^period,
               target: "foo",
               event: "external"
             }
           ] = DB.Repo.all(DB.Metrics) |> Enum.sort_by(& &1.target)

    assert %{} == :sys.get_state(Unlock.BatchMetrics)
  end
end
