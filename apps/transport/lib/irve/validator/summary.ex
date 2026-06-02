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
  loudly instead of silently rendering as `nil`. Nested values (`error_samples`,
  `column_errors`) stay as plain maps.
  """
  def from_result(result) when is_map(result) do
    struct!(__MODULE__, Map.new(result, fn {key, value} -> {String.to_existing_atom(key), value} end))
  end
end
