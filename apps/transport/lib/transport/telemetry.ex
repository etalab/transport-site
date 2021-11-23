defmodule Transport.Telemetry do
  require Logger

  @doc """

  Important: as documented here https://github.com/beam-telemetry/telemetry:

  " The handle_event callback of each handler is invoked synchronously on each telemetry:execute call. Therefore, it is extremely important
  to avoid blocking operations. If you need to perform any action that it is not immediate, consider offloading the work to a separate
  process (or a pool of processes) by sending a message. "

  """
  def handle_event(
        event = [:proxy, :request, type],
        _measurements,
        %{identifier: identifier},
        _config
      ) do
    # make it non-blocking, to ensure the traffic will be served quickly. this also means, though, we
    # won't notice if a tracing of event fails
    Task.start(fn ->
      Logger.info("Telemetry event: processing #{type} proxy request for #{identifier} data")
      count_event(identifier, event |> Enum.join(":"))
    end)
  end

  def truncate_datetime_to_minute(datetime) do
    %{DateTime.truncate(datetime, :second) | second: 0}
  end

  @doc """
  Atomically upsert a count record in the database.
  """
  def count_event(identifier, event, period \\ DateTime.utc_now()) do
    period = truncate_datetime_to_minute(period)

    DB.Repo.insert!(
      %DB.Metrics{target: identifier, event: event, period: period, count: 1},
      returning: [:count],
      conflict_target: [:target, :event, :period],
      on_conflict: [inc: [count: 1]]
    )
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
