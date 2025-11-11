defmodule Transport.IRVE.Validation.RequirednessProcessing do
  @moduledoc """
  Handles requiredness logic for field validation.

  This module combines base validation results with requiredness constraints
  to produce the final validation outcome for a field.

  ## Philosophy

  The requiredness processing is separated from base validation to maintain
  clear separation of concerns:
  - Base validation checks if a value (when present) meets its constraints
  - Requiredness processing determines if the value must be present

  ## Requiredness Logic

  When required is true: the field must be present (non-empty) AND pass base validation.
  When required is false: the field is optional - it must be empty OR pass base validation.

  This logic is expressed in terms of "requiredness" rather than "optionality"
  to align with the direction of the `required` constraint (true/false).
  """

  alias Explorer.Series
  alias Transport.IRVE.Validation.Primitives

  @doc """
  Apply requiredness constraint to base validation result.

  ## Parameters

  - `series`: The original data series
  - `base_validation`: Boolean series indicating which values pass base validation
  - `required`: Boolean indicating if the field is required

  ## Examples

      iex> alias Explorer.Series
      iex> series = Series.from_list(["", "valid", "invalid"])
      iex> base_validation = Series.from_list([false, true, false])
      iex> apply_requiredness(series, base_validation, true) |> Series.to_list()
      [false, true, false]

      iex> alias Explorer.Series
      iex> series = Series.from_list(["", "valid", "invalid"])
      iex> base_validation = Series.from_list([false, true, false])
      iex> apply_requiredness(series, base_validation, false) |> Series.to_list()
      [true, true, false]
  """
  def apply_requiredness(series, base_validation, required)

  def apply_requiredness(series, base_validation, true) do
    Series.and(Primitives.has_value(series), base_validation)
  end

  def apply_requiredness(series, base_validation, false) do
    Series.or(
      Series.not(Primitives.has_value(series)),
      base_validation
    )
  end
end
