defmodule DB.ResourceUnavailability do
  @moduledoc """
  Model used to store when a resource is not available over HTTP
  (timeout, server errors etc)
  """
  alias DB.{Repo, Resource}

  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  typed_schema "resource_unavailability" do
    field(:start, :utc_datetime)
    field(:end, :utc_datetime)
    timestamps(type: :utc_datetime_usec)

    belongs_to(:resource, Resource)
  end

  @spec ongoing_unavailability(Resource.t()) :: nil | __MODULE__.t()
  def ongoing_unavailability(%Resource{id: resource_id}) do
    __MODULE__
    |> where([r], r.resource_id == ^resource_id and is_nil(r.end))
    |> order_by([r], desc: r.start)
    |> limit(1)
    |> Repo.one()
  end

  def availability_over_last_days(%Resource{} = resource, nb_days) when is_integer(nb_days) and nb_days > 0 do
    %{hours: hours} = unavailabilities_over_last_days(resource, nb_days)
    round_float(100 - hours / (24.0 * nb_days) * 100)
  end

  @doc """
  Round a float up to a precision and removes unneeded zeroes.

  iex> round_float(1.23)
  1.2

  iex> round_float(1.0)
  1

  iex> round_float(1.20, 2)
  1.20
  """
  def round_float(float, precision \\ 1) do
    rounded = Float.round(float, precision)
    trunced = trunc(float)
    if rounded == trunced, do: trunced, else: rounded
  end

  def unavailabilities_over_last_days(%Resource{id: resource_id}, nb_days) when is_integer(nb_days) and nb_days > 0 do
    # Sorry about the messy Ecto code
    # - interval to number of hours, https://stackoverflow.com/a/952600
    rows =
      __MODULE__
      |> select([:start, :end])
      |> where([r], r.resource_id == ^resource_id)
      |> where(
        [r],
        fragment(
          ~s["end" IS NULL OR "end" between now() - '1 day'::interval * ? and now()],
          ^nb_days
        )
      )
      |> Repo.all()

    period_start = days_ago(nb_days)

    %{
      resource_id: resource_id,
      nb_periods: Enum.count(rows),
      hours: total_hours(rows, period_start)
    }
  end

  def uptime_per_day(%Resource{id: resource_id}, nb_days) do
    query = """
    with dates as
    (select day, tsrange(day, date_trunc('day', day) + interval '1 day' - interval '1 second') as day_range
    from generate_series(current_date - interval '30 day', current_date, '1 day') as day),

    down_ranges as
    (select tsrange(ru.start, ru.end) as down_range from resource_unavailability ru where ru.resource_id = $1),

    downtimes as
    (select day, sum(upper(day_range * down_range) - lower(day_range * down_range)) as downtime
    from dates cross join down_ranges dr where day_range && down_range group by day),

    uptimes as
    (select day, 1. - (EXTRACT(EPOCH from downtime) / EXTRACT(EPOCH from interval '1 day')) as uptime from downtimes)

    select dates.day::date, coalesce (uptime, 1) as uptime from dates left join uptimes on dates.day = uptimes.day;
    """

    %{columns: columns, rows: rows} = Ecto.Adapters.SQL.query!(DB.Repo, query, [resource_id])
    Enum.map(rows, fn row -> Enum.zip(columns, row) |> Map.new()
  end)
  end

  defp total_hours(rows, period_start) do
    seconds =
      rows
      |> Enum.map(fn row ->
        row_start =
          if DateTime.compare(row.start, period_start) == :lt do
            period_start
          else
            row.start
          end

        row_end = if is_nil(row.end), do: days_ago(0), else: row.end

        DateTime.diff(row_end, row_start, :second)
      end)
      |> Enum.reject(&(&1 < 0))
      |> Enum.sum()

    seconds / 3600
  end

  defp days_ago(days) when days >= 0 do
    DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second) |> DateTime.truncate(:second)
  end
end
