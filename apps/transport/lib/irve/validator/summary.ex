defmodule Transport.IRVE.Validator.Summary do
  @moduledoc """
  Struct representing the human-actionable summary produced after IRVE validation.
  """

  @enforce_keys [
    :valid,
    :valid_row_count,
    :invalid_row_count,
    :total_row_count,
    :file_level_errors,
    :column_errors,
    :error_samples
  ]

  defstruct [
    :valid,
    :valid_row_count,
    :invalid_row_count,
    :total_row_count,
    :file_level_errors,
    :column_errors,
    :error_samples
  ]

  @doc """
  Rebuilds a `%Summary{}` from its persisted map (string keys, as read back from the
  database `result` column). Uses `struct!/2` so a drifted/missing top-level key raises
  loudly instead of silently rendering as `nil`.

  `error_samples` rows are re-keyed to atoms too: their keys are a fixed set
  (`id_pdc_itinerance`, `column`, `value`) so the template keeps plain dot access.
  `column_errors` keys stay strings (they are field names, not a fixed atom set).
  """
  def from_result(result) when is_map(result) do
    result
    |> atomize_keys()
    |> Map.update!(:error_samples, fn samples -> Enum.map(samples, &atomize_keys/1) end)
    |> then(&struct!(__MODULE__, &1))
  end

  defp atomize_keys(map) do
    Map.new(map, fn {key, value} -> {String.to_existing_atom(key), value} end)
  end
end
