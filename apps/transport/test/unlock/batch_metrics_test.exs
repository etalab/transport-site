defmodule Unlock.BatchMetricsTest do
  use ExUnit.Case, async: false
  import DB.Factory
  import Unlock.Shared

  doctest Unlock.BatchMetrics, import: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    Cachex.clear(cache_name())
    on_exit(fn -> Cachex.clear(cache_name()) end)
  end

  test "work delay is less than cache expiration" do
    assert Unlock.BatchMetrics.work_delay() / 1_000 < default_cache_expiration_seconds()
  end

  test "work" do
    period = DateTime.utc_now() |> Unlock.BatchMetrics.truncate_datetime_to_hour()
    insert(:metrics, %{target: "bar", event: "internal", period: period, count: 1})

    assert Enum.empty?(metric_cache_keys())

    Cachex.incr(cache_name(), metric_cache_key(%{target: "foo", event: "external"}), 10)
    Cachex.incr(cache_name(), metric_cache_key(%{target: "bar", event: "internal"}), 2)

    Unlock.BatchMetrics.handle_info(:work, %{})

    assert [
             # Metric has been updated
             %DB.Metrics{
               count: 3,
               period: ^period,
               target: "bar",
               event: "internal"
             },
             # New metric has been inserted
             %DB.Metrics{
               count: 10,
               period: ^period,
               target: "foo",
               event: "external"
             }
           ] = DB.Repo.all(DB.Metrics) |> Enum.sort_by(& &1.target)

    assert Enum.empty?(metric_cache_keys())
  end
end
