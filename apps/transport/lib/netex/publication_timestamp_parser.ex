defmodule Transport.NeTEx.PublicationTimestampParser do
  @moduledoc """
  SAX streaming parser to extract the `PublicationTimestamp` from a NeTEx XML file.

  Returns a `Date.t() | nil`. If multiple timestamps exist across files, the
  earliest one wins (determined by the caller).
  """

  @behaviour Saxy.Handler

  import Transport.NeTEx.SaxyHelpers

  def initial_state do
    capturing_initial_state(%{timestamp: nil})
  end

  def unwrap_result(%{timestamp: timestamp}), do: timestamp

  def handle_event(:start_element, {"PublicationTimestamp", _attributes}, state) do
    {:ok, state |> push("PublicationTimestamp") |> start_capture()}
  end

  def handle_event(:end_element, "PublicationTimestamp", state) do
    {:ok, state |> stop_capture() |> pop()}
  end

  def handle_event(:characters, chars, state) when state.capture and is_nil(state.timestamp) do
    case parse_date(state, chars, fn date -> date end) do
      {:ok, %Date{} = date} ->
        {:ok, %{state | timestamp: date}}

      _ ->
        {:ok, state}
    end
  end

  def handle_event(:start_element, {element, _attributes}, state) do
    {:ok, state |> push(element)}
  end

  def handle_event(:end_element, _element, state) do
    {:ok, pop(state)}
  end

  def handle_event(_, _, state), do: {:ok, state}
end
