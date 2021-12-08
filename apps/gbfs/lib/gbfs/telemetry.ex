defmodule GBFS.Telemetry do
  @gbfs_requests [:internal, :external]

  @moduledoc """
  A quick place to centralize definition of tracing events and targets
  """
  # This call will result in synchronous invoke of all registered handlers for the specified events.
  # (for instance, check out `Transport.Telemetry#handle_event`, available at time of writing)
  def trace_request(network_name, request_type) when request_type in @gbfs_requests do
    :telemetry.execute([:gbfs, :request, request_type], %{}, %{target: target_for_network(network_name)})
  end

  def target_for_network(network_name), do: "gbfs:#{network_name}"
end
