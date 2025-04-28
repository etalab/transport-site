defmodule Transport.NeTEx.StopPlacesStreamingParser do
  @moduledoc """
  This module is a `Saxy` streaming XML parser, able to scan very large XML files
  in a way that does not overload the memory (element by element).

  It is a first stab at reading NeTEx files to pick `StopPlace`s.

  Limitations:
  - There are other locations in a NeTEx file where to find stops, and also other concepts (`Quay`),
    but this is already providing a first basis on which we'll iterate.
  - The result is an accumulated array (not a stream), which is not actually a problem given the
    current size of the output, but this could be changed in the future.
  - The scanning structure is hard-coded, and we will want later to use something more flexible
    (à la XPath), maybe via macros or real XPath calls, but this is good enough for now.

  How it works:
  - Detect `StopPlace` elements
  - Extract their `id` attribute
  - Underneath, find the `Centroid/Location/[Latitude|Longitude]` nodes

  Some `StopPlace`s do not have any `Centroid` nor `Latitude|Longitude`, but are still scanned.
  """

  @behaviour Saxy.Handler

  def get_attribute!(attributes, attr_name) do
    [value] = for {attr, value} <- attributes, attr == attr_name, do: value
    value
  end

  # NOTE: currently parsing as floats, which are limited in terms of precision,
  # but more work on precision will be done later.
  def parse_float!(binary) do
    {value, ""} = Float.parse(binary)
    value
  end

  # A `StopPlace` is declared, we will start capturing subsequent events
  def handle_event(:start_element, {"StopPlace" = element, attributes}, state) do
    if state[:capture] || not is_nil(state[:current_stop_place]) do
      raise "Invalid state"
    end

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
