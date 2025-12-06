defmodule Unlock.BatchMetrics do
  @moduledoc """
  A module to insert proxy metrics in the database every 30 seconds.
  """
  use GenServer
  import Unlock.Shared

  @work_delay :timer.seconds(5)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def work_delay, do: @work_delay

  @impl true
  def init(state) do
    schedule_work()
    {:ok, state}
  end

  @impl true
  def handle_info(:work, state) do
    keys = metric_cache_keys()
    period = DateTime.utc_now() |> truncate_datetime_to_hour()

    Cachex.transaction(cache_name(), keys, fn worker ->
      Enum.each(keys, fn key ->
        count = Cachex.get!(worker, key)

        ["", event, target] =
          key
          |> String.replace_prefix(metric_cache_prefix(), "")
          |> String.split(Unlock.Shared.cache_separator())

        DB.Repo.insert!(
          %DB.Metrics{target: target, event: event, period: period, count: count},
          returning: [:count],
          conflict_target: [:target, :event, :period],
          on_conflict: [inc: [count: count]]
        )

        Cachex.del(worker, key)
      end)
    end)

    schedule_work()

    {:noreply, state}
  end

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
