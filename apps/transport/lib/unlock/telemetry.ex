defmodule Unlock.Telemetry do
  @moduledoc """
  Telemetry event naming for the proxy.
  """

  @proxy_request_types [:external, :internal]

  def proxy_request_types, do: @proxy_request_types

  def proxy_request_event_name(request) when request in @proxy_request_types,
    do: [:proxy, :request, request]

  def proxy_request_event_names, do: @proxy_request_types |> Enum.map(&proxy_request_event_name/1)

  @separator ":"

  def target_for_identifier(item_identifier) when is_binary(item_identifier) do
    "proxy" <> @separator <> item_identifier
  end

  # aggregate feed support - which we could generalize in the future
  def target_for_identifier([item_identifier, sub_item_identifier]) do
    target_for_identifier(item_identifier <> @separator <> sub_item_identifier)
  end

  # This call will result in synchronous invoke of all registered handlers for the specified events.
  # (for instance, check out `Transport.Telemetry#handle_event`, available at time of writing)
  def trace_request(item_identifier, request_type) when request_type in @proxy_request_types do
    :telemetry.execute([:proxy, :request, request_type], %{}, %{
      target: target_for_identifier(item_identifier)
    })
  end
end
