defmodule Transport.Telemetry do
  require Logger

  def handle_event([:proxy, :request, type], _measurements, %{identifier: identifier}, _config) do
    Logger.info("Telemetry event: processing #{type} proxy request for #{identifier} data")
  end
end
