defmodule Transport.IRVE.Validator.FieldValidation do
  @moduledoc """
  Schema-driven field validation for IRVE data.

  Performs base validation based on field type, format, and constraints.
  Each function clause handles a specific combination of type/format/constraints.
  """

  alias Explorer.Series

  def perform_base_validation(df, field_name, "boolean", nil, constraints) when map_size(constraints) == 0 do
    df[field_name] |> Series.in(["true", "false"])
  end

  def perform_base_validation(df, field_name, "integer", nil, %{"minimum" => min} = constraints)
      when map_size(constraints) == 1 do
    casted = df[field_name] |> Series.cast(:integer)

    Series.and(
      Series.is_not_nil(casted),
      Series.greater_equal(casted, min)
    )
  end

  def perform_base_validation(df, field_name, "number", nil, %{"minimum" => min} = constraints)
      when map_size(constraints) == 1 do
    casted = df[field_name] |> Series.cast({:f, 64})

    Series.and(
      Series.and(
        Series.is_not_nil(casted),
        Series.is_finite(casted)
      ),
      Series.greater_equal(casted, min)
    )
  end

  def perform_base_validation(df, field_name, "string", "email", constraints) when map_size(constraints) == 0 do
    Series.re_contains(
      df[field_name],
      Transport.IRVE.Validation.Primitives.simple_email_pattern()
    )
  end

  def perform_base_validation(df, field_name, "date", fmt, constraints) when map_size(constraints) == 0 do
    true = fmt == "%Y-%m-%d"
    date_pattern = ~S/\A\d{4}\-\d{2}\-\d{2}\z/
    Series.re_contains(df[field_name], date_pattern)
  end

  def perform_base_validation(df, field_name, "geopoint", "array", constraints) when map_size(constraints) == 0 do
    geopoint_pattern = ~S/\A\[\-?\d+(\.\d+)?,\s?\-?\d+(\.\d+)?\]\z/
    Series.re_contains(df[field_name], geopoint_pattern)
  end

  def perform_base_validation(df, field_name, "string", nil, %{"pattern" => pattern_value} = constraints)
      when map_size(constraints) == 1 do
    Series.re_contains(df[field_name], pattern_value)
  end

  def perform_base_validation(df, field_name, "string", nil, %{"enum" => values} = constraints)
      when map_size(constraints) == 1 do
    df[field_name] |> Series.in(values)
  end

  def perform_base_validation(df, field_name, "string", nil, constraints) when map_size(constraints) == 0 do
    df[field_name] |> Series.equal(df[field_name])
  end

  def perform_base_validation(_df, field_name, type, format, constraints) do
    raise """
    Unhandled validation case for field: #{field_name}
    type: #{inspect(type)}
    format: #{inspect(format)}
    constraints (excluding 'required'): #{inspect(constraints)}
    """
  end

  @doc """
  Apply required/optional logic to a field validation.

  When required is true: the field must be present (non-empty) AND pass base validation.
  When required is false: the field must be empty OR pass base validation.
  """
  def apply_required_logic(series, base_validation, true) do
    Series.and(value_present?(series), base_validation)
  end

  def apply_required_logic(series, base_validation, false) do
    Series.or(
      Series.not(value_present?(series)),
      base_validation
    )
  end

  defp value_present?(series) do
    series
    |> Series.strip()
    |> Series.fill_missing("")
    |> Series.not_equal("")
  end
end
