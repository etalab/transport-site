defmodule Transport.Telemetry do
  require Logger

  @proxy_request_types [:external, :internal]

  @moduledoc """
  This place groups various aspects of event handling (currently to get metrics for the proxy, later more):
  - events handler declaration
  - upsert code to make it easy to count an event in database
  - setup code
  """

  @doc """

  Important: as documented here https://github.com/beam-telemetry/telemetry:

  " The handle_event callback of each handler is invoked synchronously on each telemetry:execute call. Therefore, it is extremely important
  to avoid blocking operations. If you need to perform any action that it is not immediate, consider offloading the work to a separate
  process (or a pool of processes) by sending a message. "

  """
  def handle_event(
        [:proxy, :request, type] = event,
        _measurements,
        %{target: target},
        _config
      )
      when type in @proxy_request_types do
    # make it non-blocking, to ensure the traffic will be served quickly. this also means, though, we
    # won't notice if a tracing of event fails
    Task.start(fn ->
      Logger.info("Telemetry event: processing #{type} proxy request for #{target}")
      count_event(target, event)
    end)
  end

  def database_event_name(event_name), do: Enum.join(event_name, ":")

  @doc """
  We embrace the fact that our current implementation's goal is not to replace
  a full-blown timeseries, by limiting the bucket timespan to 1 hour.
  """
  def truncate_datetime_to_hour(datetime) do
    %{DateTime.truncate(datetime, :second) | second: 0, minute: 0}
  end

  @doc """
  Atomically upsert a count record in the database.
  """
  def count_event(target, event, period \\ DateTime.utc_now()) do
    event = database_event_name(event)
    period = truncate_datetime_to_hour(period)

    DB.Repo.insert!(
      %DB.Metrics{target: target, event: event, period: period, count: 1},
      returning: [:count],
      conflict_target: [:target, :event, :period],
      on_conflict: [inc: [count: 1]]
    )
  end

  def proxy_request_event_name(request) when request in @proxy_request_types,
    do: [:proxy, :request, request]

  def proxy_request_event_names, do: @proxy_request_types |> Enum.map(&[:proxy, :request, &1])

  @doc """
  Attach the required handlers. To be called at application start.
  """
  def setup do
    :ok =
      :telemetry.attach_many(
        # unique handler id
        "proxy-logging-handler",
        # here we list the "event names" (a name is actually a list of atoms, per
        # https://hexdocs.pm/telemetry/telemetry.html#t:event_name/0)
        # for which we want to be called in the handler
        proxy_request_event_names(),
        &Transport.Telemetry.handle_event/4,
        nil
      )
  end
end
