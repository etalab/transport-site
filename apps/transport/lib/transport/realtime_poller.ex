defmodule Transport.RealtimePoller do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(init_arg) do
    {:ok, init_arg}
  end
end
