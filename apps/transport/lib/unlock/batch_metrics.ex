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

  @work_delay :timer.seconds(5)

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
    new_state = Map.update(state, metric_key(payload), 1, &(&1 + 1))
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:work, state) do
    period = DateTime.utc_now() |> Transport.Telemetry.truncate_datetime_to_hour()

    Enum.each(state, fn {{target, event}, count} ->
      Task.start(fn ->
        DB.Repo.insert!(
          %DB.Metrics{target: target, event: event, period: period, count: count},
          conflict_target: [:target, :event, :period],
          on_conflict: [inc: [count: count]]
        )
      end)
    end)

    schedule_work()

    {:noreply, %{}}
  end

  def metric_key(%{target: target, event: event}), do: {target, event}

  defp schedule_work do
    Process.send_after(self(), :work, @work_delay)
  end
end
