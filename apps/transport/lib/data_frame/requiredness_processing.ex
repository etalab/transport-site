defmodule Transport.DataFrame.RequirednessProcessing do
  @moduledoc """
  Wraps value validation results with requiredness constraints.

  - `required: true` - value must be present AND pass validation
  - `required: false` - value must be empty OR pass validation
  """

  alias Explorer.Series
  alias Transport.DataFrame.Validation.Primitives

  def wrap_with_requiredness(input_values_series, validation_series, required: true) do
    Series.and(
      Primitives.has_value(input_values_series),
      validation_series
    )
  end

  def wrap_with_requiredness(input_values_series, validation_series, required: false) do
    Series.or(
      Series.not(Primitives.has_value(input_values_series)),
      validation_series
    )
  end
end
