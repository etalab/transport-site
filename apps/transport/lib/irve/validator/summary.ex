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
  Rebuilds a `%Summary{}` from its persisted (JSONB, string-keyed) `result` map. `struct!/2`
  makes an unexpected top-level key raise rather than silently render as `nil`; `error_samples` rows
  are re-keyed to atoms too (fixed key set) so the template keeps plain dot access.
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
