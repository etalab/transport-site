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

    insert(:metrics, period: last_month, target: "foo", event: "bar")
    insert(:metrics, period: three_months_ago, target: "foo", event: "bar")
    insert(:metrics, period: three_months_ago |> DateTime.add(5, :hour), target: "foo", event: "bar")
    insert(:metrics, period: four_months_ago, target: "foo", event: "bar")
    insert(:metrics, period: four_months_ago, target: "foo", event: "baz")

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
    today = %{
      (DateTime.utc_now()
       |> DateTime.add(-91, :day)
       |> DateTime.truncate(:second))
      | hour: 0,
        minute: 0,
        second: 0
    }

    yesterday = today |> DateTime.add(-1, :day)
    tomorrow = today |> DateTime.add(1, :day)

    insert(:metrics, period: yesterday, target: "foo", event: "baz", count: 10)
    insert(:metrics, period: tomorrow, target: "foo", event: "baz", count: 5)
    insert(:metrics, period: today, target: "foo", event: "baz", count: 1)
    insert(:metrics, period: today |> DateTime.add(4, :hour), target: "foo", event: "baz", count: 2)
    insert(:metrics, period: today |> DateTime.add(6, :hour), target: "foo", event: "bar", count: 4)

    assert :ok == perform_job(ArchiveMetricsJob, %{"date" => today |> DateTime.to_date() |> Date.to_iso8601()})

    metrics =
      DB.Metrics
      |> select([m], [:target, :event, :count, :period])
      |> order_by([m], m.period)
      |> DB.Repo.all()

    assert [
             %DB.Metrics{target: "foo", event: "baz", period: ^yesterday, count: 10},
             %DB.Metrics{target: "foo", event: "bar", period: ^today, count: 4},
             %DB.Metrics{target: "foo", event: "baz", period: ^today, count: 3},
             %DB.Metrics{target: "foo", event: "baz", period: ^tomorrow, count: 5}
           ] = metrics
  end

  test "does not try to archive if not past the retention period" do
    insert(:metrics, period: DateTime.utc_now(), target: "foo", event: "baz", count: 10)

    assert {:cancel, _} = perform_job(ArchiveMetricsJob, %{"date" => Date.utc_today() |> Date.to_iso8601()})

    refute Enum.empty?(DB.Metrics |> DB.Repo.all())
  end
end
