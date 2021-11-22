defmodule Transport.Telemetry do
  require Logger

  @doc """

  Important: as documented here https://github.com/beam-telemetry/telemetry:

  " The handle_event callback of each handler is invoked synchronously on each telemetry:execute call. Therefore, it is extremely important
  to avoid blocking operations. If you need to perform any action that it is not immediate, consider offloading the work to a separate
  process (or a pool of processes) by sending a message. "

  """
  def handle_event([:proxy, :request, type], _measurements, %{identifier: identifier}, _config) do
    Logger.info("Telemetry event: processing #{type} proxy request for #{identifier} data")
  end


  @doc """
  Attach the required handles. To be called at application start.
  """
  def setup() do
    :ok =
      :telemetry.attach_many(
        # unique handler id
        "proxy-logging-handler",
        [
          [:proxy, :request, :external],
          [:proxy, :request, :internal]
        ],
        &Transport.Telemetry.handle_event/4,
        nil
      )
  end
end
