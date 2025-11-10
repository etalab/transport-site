defmodule Transport.IRVE.Validator.FieldValidation do
  @moduledoc """
  Schema-driven field validation for IRVE data.

  Performs base validation based on field type, format, and constraints.
  Each function clause handles a specific combination of type/format/constraints.

  This module acts as an adapter between the generic validation primitives
  and the IRVE schema-specific validation requirements.

  ## Separation of Concerns

  The `required` constraint is handled separately at a higher level by
  `apply_optionality/3`. This module's `perform_base_validation/5` receives
  constraints with "required" already removed, allowing it to focus purely on
  value validation logic (type checking, patterns, ranges, etc.) without mixing
  in presence/absence logic.

  ## Pattern Matching and map_size Guards

  Each `perform_base_validation/5` clause uses `map_size/1` guards to ensure
  the constraints map contains exactly the expected keys. This provides automatic
  detection of schema changes - if a new constraint key is added to the schema,
  the validation will fail with a clear error rather than silently accepting
  unexpected constraint combinations.

  For example, `when map_size(constraints) == 1` ensures the constraints map
  contains exactly one key (e.g., only "minimum" or only "pattern"), preventing
  cases where additional unexpected constraints might be present.
  """

  alias Explorer.Series
  alias Transport.IRVE.Validation.Primitives

  def perform_base_validation(df, field_name, "boolean", nil, constraints) when map_size(constraints) == 0 do
    Primitives.validate_boolean(df[field_name])
  end

  def perform_base_validation(df, field_name, "integer", nil, %{"minimum" => min} = constraints)
      when map_size(constraints) == 1 do
    Series.and(
      Primitives.validate_integer(df[field_name]),
      Primitives.validate_minimum(df[field_name], min)
    )
  end

  def perform_base_validation(df, field_name, "number", nil, %{"minimum" => min} = constraints)
      when map_size(constraints) == 1 do
    Series.and(
      Primitives.validate_number(df[field_name]),
      Primitives.validate_minimum(df[field_name], min)
    )
  end

  def perform_base_validation(df, field_name, "string", "email", constraints) when map_size(constraints) == 0 do
    Primitives.validate_email(df[field_name])
  end

  def perform_base_validation(df, field_name, "date", fmt, constraints) when map_size(constraints) == 0 do
    true = fmt == "%Y-%m-%d"
    Primitives.validate_date(df[field_name], "%Y-%m-%d")
  end

  def perform_base_validation(df, field_name, "geopoint", "array", constraints) when map_size(constraints) == 0 do
    Primitives.validate_geopoint(df[field_name], "array")
  end

  def perform_base_validation(df, field_name, "string", nil, %{"pattern" => pattern_value} = constraints)
      when map_size(constraints) == 1 do
    Primitives.validate_pattern(df[field_name], pattern_value)
  end

  def perform_base_validation(df, field_name, "string", nil, %{"enum" => values} = constraints)
      when map_size(constraints) == 1 do
    Primitives.validate_enum(df[field_name], values)
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
  Apply optionality logic to a field validation.

  When required is true: the field must be present (non-empty) AND pass base validation.
  When required is false: the field is optional - it must be empty OR pass base validation.
  """
  def apply_optionality(series, base_validation, true) do
    Series.and(Primitives.validate_required(series), base_validation)
  end

  def apply_optionality(series, base_validation, false) do
    Series.or(
      Series.not(Primitives.validate_required(series)),
      base_validation
    )
  end
end
