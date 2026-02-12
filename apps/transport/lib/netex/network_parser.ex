defmodule Transport.NeTEx.NetworkParser do
  @moduledoc """
  Extract network informations.
  """

  @behaviour Saxy.Handler

  import Transport.NeTEx.SaxyHelpers

  def initial_state do
    capturing_initial_state(%{
      networks: []
    })
  end

  def unwrap_result(final_state), do: final_state.networks

  def handle_event(:start_element, {element, _attributes}, state) do
    state =
      case {element, state[:capture]} do
        {"Network", _} ->
          state |> push(element) |> start_capture()

        {_, true} ->
          state |> push(element)

        _ ->
          state
      end

    {:ok, state}
  end

  def handle_event(:end_element, "Network", state) do
    {:ok, state |> stop_capture() |> pop()}
  end

  def handle_event(:end_element, _, state) do
    {:ok, state |> pop()}
  end

  def handle_event(:characters, chars, state)
      when state.capture and state.current_tree == ["Network", "Name"] do
    {:ok, state |> register_network(chars)}
  end

  def handle_event(_, _, state), do: {:ok, state}

  defp register_network(state, network), do: update_in(state, [:networks], &(&1 ++ [network]))
end
