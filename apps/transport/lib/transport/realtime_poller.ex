defmodule Transport.RealtimePoller do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def schedule_next_tick do
    Process.send_after(self(), :tick, 1_000)
  end

  def handle_info(:tick, state) do
    Logger.info "Ticking..."
    schedule_next_tick()
    {:noreply, state}
  end
end
