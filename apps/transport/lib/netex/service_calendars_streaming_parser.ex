defmodule Transport.NeTEx.ServiceCalendarsStreamingParser do
  @moduledoc """
  Saxy streaming parser to extract service calendars from a given NeTEx file.
  """

  @behaviour Saxy.Handler

  import Transport.NeTEx.SaxyHelpers

  def initial_state do
    %{
      capture: false,
      current_tree: [],
      service_calendars: []
    }
  end

  def unwrap_result(final_state), do: final_state.service_calendars

  def handle_event(:start_element, {element, attributes}, state) do
    state =
      case {element, state[:capture]} do
        {"ServiceCalendarFrame", _} ->
          state |> reset_tree() |> start_capture()

        {"ServiceCalendar", true} ->
          update_service_calendar(state, :id, get_attribute!(attributes, "id"))

        {"DayType", true} ->
          init_service_calendar(state, %{id: get_attribute!(attributes, "id")})

        {_, _} ->
          state
      end

    {:ok, state |> push(element)}
  end

  def handle_event(:end_element, node, state) do
    cond do
      node == "ServiceCalendarFrame" ->
        {:ok, state |> reset_tree() |> stop_capture()}

      node in ["ServiceCalendar", "DayType"] and state[:capture] ->
        {:ok, state |> register_service_calendar() |> pop()}

      true ->
        {:ok, pop(state)}
    end
  end

  def handle_event(:characters, chars, state)
      when state.current_tree == ["ServiceCalendarFrame", "Name"] do
    {:ok, init_service_calendar(state, %{name: chars})}
  end

  def handle_event(:characters, chars, state)
      when state.current_tree == ["ServiceCalendarFrame", "dayTypes", "DayType", "Name"] do
    {:ok, update_service_calendar(state, :name, chars)}
  end

  def handle_event(:characters, chars, state)
      when state.current_tree == ["ServiceCalendarFrame", "ServiceCalendar", "FromDate"] do
    update_date(state, :start_date, chars)
  end

  def handle_event(:characters, chars, state)
      when state.current_tree == ["ServiceCalendarFrame", "dayTypes", "DayType", "ValidBetween", "FromDate"] do
    update_date(state, :start_date, chars)
  end

  def handle_event(:characters, chars, state)
      when state.current_tree == ["ServiceCalendarFrame", "ServiceCalendar", "ToDate"] do
    update_date(state, :end_date, chars)
  end

  def handle_event(:characters, chars, state)
      when state.current_tree == ["ServiceCalendarFrame", "dayTypes", "DayType", "ValidBetween", "ToDate"] do
    update_date(state, :end_date, chars)
  end

  def handle_event(:characters, _chars, state) do
    {:ok, state}
  end

  def handle_event(_, _, state), do: {:ok, state}

  defp init_service_calendar(state, attrs), do: Map.put(state, :current_service_calendar, attrs)

  defp update_service_calendar(state, field, value) do
    update_in(state, [:current_service_calendar], &(&1 |> Map.put(field, value)))
  end

  defp push(state, element), do: state |> update_in([:current_tree], &(&1 ++ [element]))

  defp pop(state), do: update_in(state, [:current_tree], &(&1 |> List.delete_at(-1)))

  defp reset_tree(state), do: %{state | current_tree: []}

  defp start_capture(state), do: %{state | capture: true}

  defp stop_capture(state), do: %{state | capture: false}

  defp register_service_calendar(state) do
    current = state.current_service_calendar

    if valid_service_calendar?(current) do
      state
      |> init_service_calendar(nil)
      |> update_in([:service_calendars], &(&1 ++ [current]))
    else
      state
      |> init_service_calendar(nil)
    end
  end

  defp valid_service_calendar?(%{id: id, name: name, start_date: %Date{}, end_date: %Date{}}) do
    is_binary(id) and is_binary(name)
  end

  defp valid_service_calendar?(_), do: false

  defp update_date(state, field, chars) do
    parse_date(state, chars, &update_service_calendar(state, field, &1))
  end
end
