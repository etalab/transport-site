defmodule Transport.NeTEx.DescriptionParser do
  @moduledoc """
  Extract network informations.
  """

  @behaviour Saxy.Handler

  import Transport.NeTEx.SaxyHelpers

  @empty %{
    networks: [],
    transport_modes: [],
    routes: 0,
    quays: 0,
    stop_places: 0
  }

  def initial_state do
    capturing_initial_state(@empty)
  end

  def unwrap_result(final_state),
    do: final_state |> Map.take(Map.keys(@empty))

  def handle_event(:start_element, {element, _attributes}, state)
      when element in ["Network", "Line"] do
    {:ok, state |> push(element) |> start_capture()}
  end

  def handle_event(:start_element, {element, _attributes}, state)
      when state.capture do
    {:ok, state |> push(element)}
  end

  def handle_event(:end_element, element, state)
      when element in ["Network", "Line"] do
    {:ok, state |> stop_capture() |> pop()}
  end

  def handle_event(:end_element, "Route", state) do
    {:ok, state |> increment(:routes) |> pop()}
  end

  def handle_event(:end_element, "Quay", state) do
    {:ok, state |> increment(:quays) |> pop()}
  end

  def handle_event(:end_element, "StopPlace", state) do
    {:ok, state |> increment(:stop_places) |> pop()}
  end

  def handle_event(:end_element, _, state) do
    {:ok, state |> pop()}
  end

  def handle_event(:characters, chars, state)
      when state.capture and state.current_tree == ["Network", "Name"] do
    {:ok, state |> register_network(chars)}
  end

  def handle_event(:characters, chars, state)
      when state.capture and state.current_tree == ["Line", "TransportMode"] do
    {:ok, state |> register_transport_mode(chars)}
  end

  def handle_event(_, _, state), do: {:ok, state}

  defp register_network(state, network), do: update_in(state, [:networks], &(&1 ++ [network]))

  defp register_transport_mode(state, transport_mode),
    do: update_in(state, [:transport_modes], &(&1 ++ [transport_mode]))

  defp increment(state, key), do: update_in(state, [key], &(&1 + 1))
end
