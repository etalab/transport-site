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
end
