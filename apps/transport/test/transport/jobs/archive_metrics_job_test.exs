defmodule Transport.Test.Transport.Jobs.ArchiveMetricsJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Ecto.Query
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.ArchiveMetricsJob

  doctest ArchiveMetricsJob, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "enqueues jobs" do
    today = %{DateTime.utc_now() | hour: 0}
    last_month = today |> DateTime.add(-10, :day)
    three_months_ago = today |> DateTime.add(-91, :day)
    four_months_ago = today |> DateTime.add(-30 * 4, :day)
    five_months_ago = today |> DateTime.add(-30 * 5, :day)

    insert(:metrics, period: last_month, target: "foo", event: "bar")
    insert(:metrics, period: three_months_ago, target: "foo", event: "bar")
    insert(:metrics, period: three_months_ago |> DateTime.add(5, :hour), target: "foo", event: "bar")
    insert(:metrics, period: four_months_ago, target: "foo", event: "baz")
    insert(:metrics, period: four_months_ago |> DateTime.add(2, :hour), target: "foo", event: "baz")
    # Don't need to process as we have a single line per (period, target, event)
    insert(:metrics, period: five_months_ago, target: "foo", event: "baz")
    insert(:metrics, period: five_months_ago, target: "foo", event: "bar")
    insert(:metrics, period: five_months_ago, target: "baz", event: "bar")

    assert :ok == perform_job(ArchiveMetricsJob, %{})

    three_months_ago_date = three_months_ago |> DateTime.to_date() |> Date.to_iso8601()
    four_months_ago_date = four_months_ago |> DateTime.to_date() |> Date.to_iso8601()

    assert [
             %Oban.Job{
               state: "scheduled",
               worker: "Transport.Jobs.ArchiveMetricsJob",
               args: %{"date" => ^three_months_ago_date}
             },
             %Oban.Job{
               state: "scheduled",
               worker: "Transport.Jobs.ArchiveMetricsJob",
               args: %{"date" => ^four_months_ago_date}
             }
           ] = all_enqueued()
  end

  test "archives rows for a given day" do
    test_date = %{
      (DateTime.utc_now()
       |> DateTime.add(-91, :day)
       |> DateTime.truncate(:second))
      | hour: 0,
        minute: 0,
        second: 0
    }

    day_before = test_date |> DateTime.add(-1, :day)
    day_after = test_date |> DateTime.add(1, :day)

    insert(:metrics, period: day_before, target: "foo", event: "baz", count: 10)
    insert(:metrics, period: day_after, target: "foo", event: "baz", count: 5)
    insert(:metrics, period: test_date, target: "foo", event: "baz", count: 1)
    insert(:metrics, period: test_date |> DateTime.add(4, :hour), target: "foo", event: "baz", count: 2)
    insert(:metrics, period: test_date |> DateTime.add(6, :hour), target: "foo", event: "bar", count: 4)

    assert :ok == perform_job(ArchiveMetricsJob, %{"date" => test_date |> DateTime.to_date() |> Date.to_iso8601()})

    metrics =
      DB.Metrics
      |> select([m], [:target, :event, :count, :period])
      |> order_by([m], m.period)
      |> DB.Repo.all()

    assert [
             %DB.Metrics{target: "foo", event: "baz", period: ^day_before, count: 10},
             %DB.Metrics{target: "foo", event: "bar", period: ^test_date, count: 4},
             %DB.Metrics{target: "foo", event: "baz", period: ^test_date, count: 3},
             %DB.Metrics{target: "foo", event: "baz", period: ^day_after, count: 5}
           ] = metrics
  end

  test "does not try to archive if not past the retention period" do
    insert(:metrics, period: DateTime.utc_now(), target: "foo", event: "baz", count: 10)

    assert {:cancel, _} = perform_job(ArchiveMetricsJob, %{"date" => Date.utc_today() |> Date.to_iso8601()})

    refute Enum.empty?(DB.Metrics |> DB.Repo.all())
  end
end
