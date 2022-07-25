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
    floor_float(100 - hours / (24.0 * nb_days) * 100)
  end

  @doc """
  Floors a float up to a precision and removes unneeded zeroes.

  See [Float.floor/2](https://hexdocs.pm/elixir/Float.html#floor/2-known-issues) for gotchas.

  iex> floor_float(1.23)
  1.2
  iex> floor_float(1.0)
  1
  iex> floor_float(1.20, 2)
  1.19
  iex> floor_float(99.98)
  99.9
  """
  def floor_float(float, precision \\ 1) do
    rounded = Float.floor(float, precision)
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
          ~s["end" IS NULL OR "end" between (now() at time zone 'UTC') - '1 day'::interval * ? and (now() at time zone 'UTC')],
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
    (select day, tsrange(day, case when day = current_date then timezone('utc', now()) else date_trunc('day', day) + interval '1 day' - interval '1 second' end) as day_range
    from generate_series(current_date - $1 * interval '1 day', current_date, '1 day') as day),

    down_ranges as
    (select tsrange(ru.start, coalesce(ru.end, timezone('utc', now()))) as down_range from resource_unavailability ru where ru.resource_id = $2),

    downtimes as
    (select day, sum(upper(day_range * down_range) - lower(day_range * down_range)) as downtime, extract('epoch' from upper(day_range) - lower(day_range)) as day_length
    from dates cross join down_ranges dr where day_range && down_range group by day, day_range),

    uptimes as
    (select day, 1. - (EXTRACT(EPOCH from downtime) / day_length) as uptime from downtimes)

    select dates.day::date, cast(coalesce (uptime, 1) as double precision) as uptime from dates left join uptimes on dates.day = uptimes.day;
    """

    %{columns: columns, rows: rows} = Ecto.Adapters.SQL.query!(DB.Repo, query, [nb_days, resource_id])

    rows |> Enum.map(fn row -> columns |> Enum.zip(row) |> Map.new() end)
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
