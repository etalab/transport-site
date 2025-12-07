defmodule Unlock.EventIncrementer do
  @moduledoc """
  A module to increment counters for events.
  """
  @callback incr_event(map()) :: :ok

  def impl, do: Application.get_env(:transport, :unlock_event_incrementer)
end

defmodule Unlock.BatchMetrics do
  @moduledoc """
  A module to insert proxy metrics in the database every 30 seconds.
  """
  use GenServer
  @behaviour Unlock.EventIncrementer

  @work_delay :timer.seconds(30)

  def work_delay, do: @work_delay

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_work()
    {:ok, state}
  end

  @impl Unlock.EventIncrementer
  def incr_event(%{target: target, event: event}) do
    GenServer.cast(__MODULE__, {:incr_event, %{target: target, event: event}})
  end

  @impl true
  def handle_cast({:incr_event, %{target: _target, event: _event} = payload}, state) do
    {_, new_state} =
      Map.get_and_update(state, metric_key(payload), fn current_value ->
        {current_value, (current_value || 0) + 1}
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:work, state) do
    period = DateTime.utc_now() |> truncate_datetime_to_hour()

    Enum.each(state, fn {key, count} ->
      [event, target] = key |> String.split(metric_separator())

      DB.Repo.insert!(
        %DB.Metrics{target: target, event: event, period: period, count: count},
        returning: [:count],
        conflict_target: [:target, :event, :period],
        on_conflict: [inc: [count: count]]
      )
    end)

    schedule_work()

    {:noreply, %{}}
  end

  def metric_key(%{target: target, event: event}) do
    Enum.join([event, target], metric_separator())
  end

  def metric_separator, do: "@"

  @doc """
  iex> truncate_datetime_to_hour(~U[2021-11-22 14:28:06.098765Z])
  ~U[2021-11-22 14:00:00Z]
  """
  def truncate_datetime_to_hour(datetime) do
    %{DateTime.truncate(datetime, :second) | second: 0, minute: 0}
  end

  defp schedule_work do
    Process.send_after(self(), :work, @work_delay)
  end
end
