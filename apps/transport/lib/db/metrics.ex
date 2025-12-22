defmodule DB.Metrics do
  @moduledoc """
  A quick metric schema to count bucketed events, until a moment may come
  where we'll outgrow this and use timescaledb or similar instead.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  typed_schema "metrics" do
    field(:target, :string)
    field(:event, :string)
    field(:period, :utc_datetime)
    field(:count, :integer)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Counts the number of external and internal request for a resource over a given
  number of days.
  """
  def requests_over_last_days(%DB.Resource{} = resource, days) when is_integer(days) and days > 0 do
    namespace = DB.Resource.proxy_namespace(resource)
    date_from = %{DateTime.utc_now() | hour: 0, minute: 0, second: 0} |> DateTime.add(-days, :day)
    target = Enum.join([namespace, DB.Resource.proxy_slug(resource)], ":")
    external_event = Enum.join([namespace, "request", "external"], ":")
    internal_event = Enum.join([namespace, "request", "internal"], ":")

    query =
      from(m in DB.Metrics,
        group_by: fragment("date"),
        order_by: fragment("date"),
        where: m.period >= ^date_from and m.target == ^target,
        select: %{
          date: fragment("?::date as date", m.period),
          requests_external:
            fragment(
              "sum(case when ? = ? then ? else 0 end) as requests_external",
              m.event,
              ^external_event,
              m.count
            ),
          requests_internal:
            fragment(
              "sum(case when ? = ? then ? else 0 end) as requests_internal",
              m.event,
              ^internal_event,
              m.count
            )
        }
      )

    query |> DB.Repo.all()
  end

  def proxy_requests(resources) do
    targets =
      Enum.map(resources, fn resource ->
        Enum.join([DB.Resource.proxy_namespace(resource), DB.Resource.proxy_slug(resource)], ":")
      end)

    from(m in DB.Metrics,
      group_by: [fragment("month"), m.target, m.event],
      order_by: [fragment("month"), m.event, m.target],
      where: m.target in ^targets,
      select: %{
        month: fragment("left(?::varchar, 7) as month", m.period),
        target: m.target,
        event: m.event,
        count: sum(m.count)
      }
    )
    |> DB.Repo.all()
  end

  @doc """
  A function to compute the total count of event per identifier/event
  for the last N days. You can optionally keep only a given
  list of events.
  """
  def for_last_days(days, only_events \\ []) when is_integer(days) and days > 0 do
    date_from = DateTime.add(DateTime.utc_now(), -days * 24 * 60 * 60, :second)

    filter_events =
      if Enum.empty?(only_events) do
        true
      else
        dynamic([m], m.event in ^only_events)
      end

    query =
      from(m in DB.Metrics,
        group_by: [m.target, m.event],
        where: m.period >= ^date_from,
        where: ^filter_events,
        select: %{sum: sum(m.count), target: m.target, event: m.event}
      )

    query
    |> DB.Repo.all()
    |> Enum.group_by(fn x -> x[:target] end)
    |> Enum.into(%{}, fn {k, v} ->
      {k, Enum.into(v, %{}, fn x -> {x[:event], x[:sum]} end)}
    end)
  end
end
