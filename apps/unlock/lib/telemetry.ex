defmodule Unlock.Telemetry do
  @moduledoc """
  Telemetry event naming for the proxy.
  """

  @proxy_request_types [:external, :internal]
  @gbfs_request_types [:external, :internal]

  def proxy_request_types, do: @proxy_request_types
  def gbfs_request_types, do: @gbfs_request_types

  def proxy_request_event_name(request) when request in @proxy_request_types,
    do: [:proxy, :request, request]

  def proxy_request_event_names, do: @proxy_request_types |> Enum.map(&proxy_request_event_name/1)

  def gbfs_request_event_name(request) when request in @gbfs_request_types,
    do: [:gbfs, :request, request]

  def gbfs_request_event_names, do: @gbfs_request_types |> Enum.map(&gbfs_request_event_name/1)

  # TODO: verify scope - this has been backported from controller

  # NOTE: to be DRYed with what is in the "transport" app later (`telemetry.ex`), if we stop using an umbrella app.
  # Currently we would have a circular dependency, or would have to move all this to `shared`.

  @proxy_requests [:internal, :external]

  def target_for_identifier(item_identifier) do
    "proxy:#{item_identifier}"
  end

  # This call will result in synchronous invoke of all registered handlers for the specified events.
  # (for instance, check out `Transport.Telemetry#handle_event`, available at time of writing)
  def trace_request(item_identifier, request_type) when request_type in @proxy_requests do
    :telemetry.execute([:proxy, :request, request_type], %{}, %{
      target: target_for_identifier(item_identifier)
    })
  end
end
