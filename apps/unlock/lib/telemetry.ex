defmodule Unlock.Telemetry do
  @moduledoc """
  Telemetry event naming for the proxy.
  """

  @proxy_request_types [:external, :internal]
  @gbfs_request_types [:external, :internal]

  def proxy_request_types(), do: @proxy_request_types
  def gbfs_request_types(), do: @gbfs_request_types

  def proxy_request_event_name(request) when request in @proxy_request_types,
    do: [:proxy, :request, request]

  def proxy_request_event_names, do: @proxy_request_types |> Enum.map(&proxy_request_event_name/1)

  def gbfs_request_event_name(request) when request in @gbfs_request_types,
    do: [:gbfs, :request, request]

  def gbfs_request_event_names, do: @gbfs_request_types |> Enum.map(&gbfs_request_event_name/1)
end
