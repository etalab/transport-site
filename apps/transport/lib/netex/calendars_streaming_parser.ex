defmodule Transport.NeTEx.CalendarsStreamingParser do
  @moduledoc """
  Saxy streaming parser to extract service calendars from a given NeTEx file.
  """

  @behaviour Saxy.Handler

  import Transport.NeTEx.NeTExHelpers
  import Transport.NeTEx.SaxyHelpers

  def initial_state do
    %{
      capture: false,
      current_tree: [],
      calendars: [],
      operating_periods: []
    }
  end

  def unwrap_result(final_state), do: final_state.calendars ++ final_state.operating_periods

  def handle_event(:start_element, {element, attributes}, state) do
    state =
      case {element, state[:capture]} do
        {"GeneralFrame", false} ->
          id = get_attribute!(attributes, "id")
          state |> reset_tree() |> start_capture() |> init_calendar(%{id: id})

        {"TypeOfFrameRef", true} ->
          type_of_frame = get_attribute!(attributes, "ref")
          state |> set_is_calendar(calendar_frame?(type_of_frame))

        {"UicOperatingPeriod", true} ->
          id = get_attribute!(attributes, "id")
          state |> init_operating_period(%{id: id})

        {_, _} ->
          state
      end

    {:ok, state |> push(element)}
  end

  def handle_event(:end_element, "GeneralFrame", state) do
    {:ok, state |> register_calendar() |> reset_tree() |> stop_capture()}
  end

  def handle_event(:end_element, "UicOperatingPeriod", state) do
    {:ok, state |> register_operating_period() |> pop()}
  end

  def handle_event(:end_element, _, state) do
    {:ok, pop(state)}
  end

  def handle_event(:characters, chars, state)
      when state.capture and state.current_tree == ["GeneralFrame", "ValidBetween", "FromDate"] do
    update_calendar_date(state, :start_date, chars)
  end

  def handle_event(:characters, chars, state)
      when state.capture and state.current_tree == ["GeneralFrame", "ValidBetween", "ToDate"] do
    update_calendar_date(state, :end_date, chars)
  end

  def handle_event(:characters, chars, state)
      when state.capture and state.current_tree == ["GeneralFrame", "members", "UicOperatingPeriod", "FromDate"] do
    update_operating_period_date(state, :start_date, chars)
  end

  def handle_event(:characters, chars, state)
      when state.capture and state.current_tree == ["GeneralFrame", "members", "UicOperatingPeriod", "ToDate"] do
    update_operating_period_date(state, :end_date, chars)
  end

  def handle_event(_, _, state), do: {:ok, state}

  defp init_calendar(state, attrs \\ %{}), do: Map.put(state, :current_calendar, attrs)

  defp update_calendar(state, field, value) do
    update_in(state, [:current_calendar], &(&1 |> Map.put(field, value)))
  end

  defp init_operating_period(state, attrs \\ %{}), do: Map.put(state, :current_operating_period, attrs)

  defp update_operating_period(state, field, value) do
    update_in(state, [:current_operating_period], &(&1 |> Map.put(field, value)))
  end

  defp set_is_calendar(state, bool), do: update_calendar(state, :is_calendar, bool)

  defp push(state, element), do: state |> update_in([:current_tree], &(&1 ++ [element]))

  defp pop(state), do: update_in(state, [:current_tree], &(&1 |> List.delete_at(-1)))

  defp reset_tree(state), do: %{state | current_tree: []}

  defp start_capture(state), do: %{state | capture: true}

  defp stop_capture(state), do: %{state | capture: false}

  defp register_calendar(state) do
    current = state.current_calendar

    if valid_calendar?(current) do
      state
      |> init_calendar()
      |> update_in([:calendars], &(&1 ++ [Map.delete(current, :is_calendar)]))
    else
      init_calendar(state)
    end
  end

  defp valid_calendar?(%{is_calendar: true, id: id, start_date: %Date{}, end_date: %Date{}}) do
    is_binary(id)
  end

  defp valid_calendar?(_), do: false

  defp update_calendar_date(state, field, chars) do
    parse_date(state, chars, &update_calendar(state, field, &1))
  end

  defp register_operating_period(state) do
    current = state.current_operating_period

    if valid_operating_period?(current) do
      state
      |> init_operating_period()
      |> update_in([:operating_periods], &(&1 ++ [current]))
    else
      init_operating_period(state)
    end
  end

  defp valid_operating_period?(%{id: id, start_date: %Date{}, end_date: %Date{}}) do
    is_binary(id)
  end

  defp valid_operating_period?(_), do: false

  defp update_operating_period_date(state, field, chars) do
    parse_date(state, chars, &update_operating_period(state, field, &1))
  end
end
