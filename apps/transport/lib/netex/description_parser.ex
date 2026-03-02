defmodule Transport.NeTEx.DescriptionParser do
  @moduledoc """
  Extract network informations.
  """

  @behaviour Saxy.Handler

  import Transport.NeTEx.SaxyHelpers

  def initial_state do
    capturing_initial_state(%{
      networks: [],
      transport_modes: []
    })
  end

  def unwrap_result(final_state), do: final_state |> Map.take([:networks, :transport_modes])

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
end
