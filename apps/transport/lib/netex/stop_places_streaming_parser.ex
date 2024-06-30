defmodule Transport.NeTEx.StopPlacesStreamingParser do
  @behaviour Saxy.Handler
  import ExUnit.Assertions

  def get_attribute!(attributes, attr_name) do
    [value] = for {attr, value} <- attributes, attr == attr_name, do: value
    value
  end

  def parse_float!(binary) do
    {value, ""} = Float.parse(binary)
    value
  end

  # A `StopPlace` is declared, we will start capturing subsequent events
  def handle_event(:start_element, {"StopPlace" = element, attributes}, state) do
    assert state[:current_stop_place] == nil
    assert state[:capture] != true

    {:ok,
     state
     |> Map.put(:current_stop_place, %{id: get_attribute!(attributes, "id")})
     |> Map.put(:capture, true)
     |> Map.put(:current_tree, [element])}
  end

  def handle_event(:start_element, {element, _attributes}, state) when state.capture do
    {:ok, state |> update_in([:current_tree], &(&1 ++ [element]))}
  end

  def handle_event(:end_element, "StopPlace" = _node, state) do
    state = if state[:callback], do: state[:callback].(state), else: state
    {:ok, %{state | current_stop_place: nil, capture: false, current_tree: []}}
  end

  def handle_event(:end_element, _node, state) do
    {:ok, state |> update_in([:current_tree], &(&1 |> List.delete_at(-1)))}
  end

  def handle_event(:characters, chars, state) when state.current_tree == ["StopPlace", "Name"] do
    {:ok, state |> update_in([:current_stop_place], &(&1 |> Map.put(:name, chars)))}
  end

  def handle_event(:characters, chars, state)
      when state.current_tree == ["StopPlace", "Centroid", "Location", "Latitude"] do
    {:ok, state |> update_in([:current_stop_place], &(&1 |> Map.put(:latitude, parse_float!(chars))))}
  end

  def handle_event(:characters, chars, state)
      when state.current_tree == ["StopPlace", "Centroid", "Location", "Longitude"] do
    {:ok, state |> update_in([:current_stop_place], &(&1 |> Map.put(:longitude, parse_float!(chars))))}
  end

  def handle_event(_, _, state), do: {:ok, state}
end
