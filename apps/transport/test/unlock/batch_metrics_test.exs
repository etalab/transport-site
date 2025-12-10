defmodule Unlock.BatchMetricsTest do
  use ExUnit.Case, async: false
  import DB.Factory

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    # because the upserts happen in a separate process (the GenServer),
    # we must tweak the sandbox to be able to see them from here
    pid = Process.whereis(Unlock.BatchMetrics)
    Ecto.Adapters.SQL.Sandbox.allow(DB.Repo, self(), pid)
    :ok
  end

  test "work" do
    now = DateTime.utc_now()
    truncated_period = now |> Transport.Telemetry.truncate_datetime_to_hour()
    insert(:metrics, %{target: "bar", event: "internal", period: truncated_period, count: 1})

    Unlock.BatchMetrics.incr_event(%{target: "foo", event: "external"})
    Unlock.BatchMetrics.incr_event(%{target: "foo", event: "external"})
    Unlock.BatchMetrics.incr_event(%{target: "foo", event: "external"})
    Unlock.BatchMetrics.incr_event(%{target: "bar", event: "internal"})

    assert %{{"foo", "external"} => 3, {"bar", "internal"} => 1} == :sys.get_state(Unlock.BatchMetrics)

    send(Unlock.BatchMetrics, :work)
    :timer.sleep(100)

    assert [
             # Metric has been updated
             %DB.Metrics{
               count: 2,
               period: ^truncated_period,
               target: "bar",
               event: "internal"
             },
             # New metric has been inserted
             %DB.Metrics{
               count: 3,
               period: ^truncated_period,
               target: "foo",
               event: "external"
             }
           ] = DB.Repo.all(DB.Metrics) |> Enum.sort_by(& &1.target)

    assert %{} == :sys.get_state(Unlock.BatchMetrics)
  end
end
