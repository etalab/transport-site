defmodule Transport.Jobs.ArchiveMetricsJob do
  @moduledoc """
  This job is in charge of archiving `DB.Metrics` after a given period.

  For rows older than `@days_before_archiving` days, we keep a single row
  per day, target and event.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  @days_before_archiving 90

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) when is_nil(args) or args == %{} do
    days_to_archive()
    |> Enum.with_index()
    |> Enum.map(fn {date, index} ->
      %{date: date} |> new(schedule_in: index * 60)
    end)
    |> Oban.insert_all()

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"date" => date}}) do
    date = Date.from_iso8601!(date)

    if Date.compare(date, Date.utc_today() |> Date.add(-@days_before_archiving)) == :gt do
      {:cancel, "Cannot archive rows if they are not older than #{@days_before_archiving} days"}
    else
      {date_start, date_end} = {to_midnight_datetime(date), date |> Date.add(1) |> to_midnight_datetime()}

      metrics =
        DB.Metrics
        |> where([m], m.period >= ^date_start and m.period < ^date_end)
        |> group_by([m], [m.target, m.event, fragment("date")])
        |> select([m], %{
          target: m.target,
          event: m.event,
          date: fragment("date(?) as date", m.period),
          total: sum(m.count)
        })
        |> DB.Repo.all()

      DB.Repo.transaction(fn ->
        DB.Metrics
        |> where([m], m.period >= ^date_start and m.period < ^date_end)
        |> DB.Repo.delete_all()

        records =
          Enum.map(metrics, fn record ->
            now = DateTime.utc_now()

            %{
              target: record.target,
              event: record.event,
              period: to_midnight_datetime(record.date),
              count: record.total,
              inserted_at: now,
              updated_at: now
            }
          end)

        DB.Repo.insert_all(DB.Metrics, records)
      end)

      :ok
    end
  end

  @doc """
  iex> to_midnight_datetime(~D[2022-12-29])
  ~U[2022-12-29 00:00:00Z]
  """
  def to_midnight_datetime(%Date{} = date) do
    {:ok, datetime, 0} = DateTime.from_iso8601("#{Date.to_iso8601(date)} 00:00:00Z")
    datetime
  end

  def days_to_archive do
    limit_date = DateTime.utc_now() |> DateTime.add(-@days_before_archiving, :day)

    DB.Metrics
    |> where([m], m.period <= ^limit_date)
    |> select([m], fragment("date(?) as date", m.period))
    |> order_by([m], fragment("date"))
    |> distinct(true)
    |> DB.Repo.all()
  end
end
