defmodule Transport.RealtimePoller do
  use GenServer
  require Logger

  def init(state) do
    # initial schedule is immediate, but via the same code path,
    # to ensure we jump on the data
    schedule_next_tick(0)
    {:ok, state}
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def schedule_next_tick(delay \\ 5_000) do
    Process.send_after(self(), :tick, delay)
  end

  def handle_info(:tick, state) do
    Logger.info "Ticking..."
    schedule_next_tick()
    {:noreply, state}
  end
end
