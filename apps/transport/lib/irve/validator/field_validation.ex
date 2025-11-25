defmodule Transport.IRVE.Validator.FieldValidation do
  @moduledoc """
  Schema-driven field validation for IRVE data.

  Compute column validity based on field type, format, and constraints.
  Each function clause handles a specific combination of type/format/constraints.

  This module acts as an adapter between the generic validation primitives
  and the IRVE schema-specific validation requirements.

  ## Separation of Concerns

  The `required` constraint is handled separately by the RequirednessProcessing module.
  This module's `column_valid?/5` receives constraints with "required" already removed,
  allowing it to focus purely on value validation logic (type checking, patterns, ranges, etc.)
  without mixing in presence/absence logic.

  ## Pattern Matching and map_size Guards

  ⚠️ If you modify this code: the order & definitions of the pattern-matched clauses is
  important and a bit delicate (like a processing pipeline) to ensure it will behave as expected.

  Each `column_valid?/5` clause uses `map_size/1` guards to ensure
  the constraints map contains exactly the expected keys. This provides automatic
  detection of schema changes - if a new constraint key is added to the schema,
  the validation will fail with a clear error rather than silently accepting
  unexpected constraint combinations.

  For example, `when map_size(constraints) == 1` ensures the constraints map
  contains exactly one key (e.g., only "minimum" or only "pattern"), preventing
  cases where additional unexpected constraints might be present.

  ## Testing

  There are no tests here, instead this logic is invoked & tested
  through `Transport.IRVE.Validator.DataFrameValidation`.
  """

  alias Explorer.Series
  alias Transport.DataFrame.Validation.Primitives

  @doc """
  Check if a dataframe column is valid according to schema specifications.

  ## Parameters

    * `df` - `Explorer.DataFrame` containing the data to validate
    * `field_name` - Column name from schema (string)
    * `field_type` - Field type: "integer", "string", "boolean", "date", "number", or "geopoint"
    * `format` - Optional format: "email", "array", or date format string
    * `constraints` - Validation constraints: `%{"minimum" => n}`, `%{"pattern" => "regex"}`, or `%{"enum" => ["val1", "val2"]}`

  Note: The `"required"` constraint must be removed before calling this function.

  ## Returns

  `Explorer.Series` of booleans where `true` means valid, `false` means invalid.
  """
  def column_valid?(df, field_name, "boolean", nil, constraints) when map_size(constraints) == 0 do
    Primitives.boolean_value?(df[field_name])
  end

  def column_valid?(df, field_name, "integer", nil, %{"minimum" => min} = constraints)
      when map_size(constraints) == 1 do
    Series.and(
      Primitives.integer_value?(df[field_name]),
      Primitives.is_greater_or_equal(df[field_name], min)
    )
  end

  def column_valid?(df, field_name, "number", nil, %{"minimum" => min} = constraints)
      when map_size(constraints) == 1 do
    Series.and(
      Primitives.numeric?(df[field_name]),
      Primitives.is_greater_or_equal(df[field_name], min)
    )
  end

  def column_valid?(df, field_name, "string", "email", constraints) when map_size(constraints) == 0 do
    Primitives.email?(df[field_name])
  end

  def column_valid?(df, field_name, "date", fmt, constraints) when map_size(constraints) == 0 do
    Primitives.date?(df[field_name], fmt)
  end

  def column_valid?(df, field_name, "geopoint", "array", constraints) when map_size(constraints) == 0 do
    Primitives.geopoint?(df[field_name], "array")
  end

  def column_valid?(df, field_name, "string", nil, %{"pattern" => pattern_value} = constraints)
      when map_size(constraints) == 1 do
    Primitives.is_matching_the_pattern(df[field_name], pattern_value)
  end

  def column_valid?(df, field_name, "string", nil, %{"enum" => values} = constraints)
      when map_size(constraints) == 1 do
    Primitives.is_in_enum(df[field_name], values)
  end

  def column_valid?(df, field_name, "string", nil, constraints) when map_size(constraints) == 0 do
    df[field_name] |> Series.equal(df[field_name])
  end

  def column_valid?(_df, field_name, type, format, constraints) do
    raise """
    Unhandled validation case for field: #{field_name}
    type: #{inspect(type)}
    format: #{inspect(format)}
    constraints (excluding 'required'): #{inspect(constraints)}
    """
  end
end
