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
