defmodule Transport.NeTEx.SaxyHelpers do
  @moduledoc """
  Helpers to implement Saxy handlers.
  """

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

  def parse_date(state, chars, cb) do
    case DateTime.from_iso8601(chars) do
      {:ok, valid, _offset} ->
        {:ok, valid |> DateTime.to_date() |> cb.()}

      _ ->
        parse_date_utc(state, chars, cb)
    end
  end

  defp parse_date_utc(state, chars, cb) do
    case DateTime.from_iso8601("#{chars}Z") do
      {:ok, valid, 0} ->
        {:ok, valid |> DateTime.to_date() |> cb.()}

      _ ->
        case Date.from_iso8601(chars) do
          {:ok, valid} -> {:ok, cb.(valid)}
          _ -> {:ok, state}
        end
    end
  end

  def capturing_initial_state(initial_state) do
    Map.merge(initial_state, %{
      capture: false,
      current_tree: []
    })
  end

  def push(state, element), do: state |> update_in([:current_tree], &(&1 ++ [element]))

  def pop(state), do: update_in(state, [:current_tree], &(&1 |> List.delete_at(-1)))

  def reset_tree(state), do: %{state | current_tree: []}

  def start_capture(state), do: %{state | capture: true}

  def stop_capture(state), do: %{state | capture: false}
end
