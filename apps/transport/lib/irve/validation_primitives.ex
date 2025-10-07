defmodule Transport.IRVE.Validation.Primitives do
  @moduledoc """
  Extracted from real-life use, this module provides a set of primitives allowing us
  to implement an Explorer-backed validator for the IRVE static schema
  (or other TableSchema schemas if needed).

  This implements a subset of what is described here https://specs.frictionlessdata.io/table-schema/.

  Implementation supports all the formats/constraints/checks defined in `schema-irve-statique.json`.

  How it works: each computation adds a new column, with a well-defined name, containing a boolean
  to state if the check has passed or not. In some cases, the outcome can be `nil` as well (not evaluated or not relevant).

  Known limitations & things to fix/improve later:
  - Outcome of check (`true`/`false`/`nil`) is not completely consistent between checks at this point.
  - Stripping / empty strings / nil values is not completely consistent between the various checks at the moment (that will change).
  - Some checks use different strategies (e.g. casting by Polars for floats, versus regex for geopoint) for practical reasons.
  - Overflow management is not completely consistent between `number` and `required` checks.
  """

  # Single source of truth for naming convention: generate check column names following
  # the pattern check_{field}_{category}_{name}
  defp build_check_column_name(field, :required), do: "check_#{field}_required"
  defp build_check_column_name(field, {:constraint, name}), do: "check_#{field}_constraint_#{name}"
  defp build_check_column_name(field, {:format, name}), do: "check_#{field}_format_#{name}"
  defp build_check_column_name(field, {:type, name}), do: "check_#{field}_type_#{name}"

  @doc """
  Given a field with `required: true` constraint, compute a column asserting that the check passes.

  The `required: false` is not implemented here, as we'll just skip the calculation in that case.

  Valid cases:

  iex> compute_required_check(build_df("field", [" something "]), "field", true) |> df_values(:check_field_required)
  [true]

  Invalid cases:

  iex> compute_required_check(build_df("field", [nil, "   "]), "field", true) |> df_values(:check_field_required)
  [false, false]
  """
  def compute_required_check(%Explorer.DataFrame{} = df, field, true = _is_required?) do
    column_check_name = build_check_column_name(field, :required)

    Explorer.DataFrame.mutate_with(df, fn df ->
      outcome =
        df[field]
        |> Explorer.Series.strip()
        |> Explorer.Series.fill_missing("")
        |> Explorer.Series.not_equal("")

      %{column_check_name => outcome}
    end)
  end

  @doc """
  Given a `pattern: xyz` constraint, compute a column asserting that the regexp is respected.
  The regexp is described via a "string pattern" (as expected by Explorer), not by an Elixir regexp.
  So far, the regexp format for Explorer/Polars has appeared to be compatible with what is used in TableSchema.

  Valid cases:

  iex> compute_constraint_pattern_check(build_df("field", ["123456789"]), "field", ~S/^\\d{9}$/) |> df_values(:check_field_constraint_pattern)
  [true]

  Invalid cases (note the `nil` occurrence):

  iex> compute_constraint_pattern_check(build_df("field", [nil, "   ", " something ", "12345678"]), "field", ~S/^\\d{9}$/) |> df_values(:check_field_constraint_pattern)
  [nil, false, false, false]
  """
  def compute_constraint_pattern_check(%Explorer.DataFrame{} = df, field, pattern) when is_binary(pattern) do
    column_check_name = build_check_column_name(field, {:constraint, :pattern})

    Explorer.DataFrame.mutate_with(df, fn df ->
      outcome = df[field] |> Explorer.Series.re_contains(pattern)
      %{column_check_name => outcome}
    end)
  end

  # NOTE: a fully compliant email regexp is a beast, not found in the Elixir stdlib, so
  # going with something simple for now, & we will improve as needed / if needed.
  @simple_email_pattern ~S/(?i)\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  @doc """
  Given a `format: "email"` field specifier, compute a column asserting that the format is verified.

  Valid cases:

  iex> compute_format_email_check(build_df("field", ["hello@example.com"]), "field") |> df_values(:check_field_format_email)
  [true]

  Invalid cases (note the `nil` occurrence):

  iex> compute_format_email_check(build_df("field", [nil, "   ", "hello@fool"]), "field") |> df_values(:check_field_format_email)
  [nil, false, false]
  """
  def compute_format_email_check(%Explorer.DataFrame{} = df, field) do
    column_check_name = build_check_column_name(field, {:format, :email})

    Explorer.DataFrame.mutate_with(df, fn df ->
      outcome = df[field] |> Explorer.Series.re_contains(@simple_email_pattern)
      %{column_check_name => outcome}
    end)
  end

  @doc """
  Given a `enum: [a,b,c]` constraint specifier, compute a column asserting that the value is one of the values in the enum.

  Valid cases:

  iex> allowed_enum_values = ["Voirie", "Parking privé réservé à la clientèle"]
  iex> compute_constraint_enum_check(build_df("field", ["Voirie"]), "field", allowed_enum_values) |> df_values(:check_field_constraint_enum)
  [true]

  Invalid cases (note the `nil` occurrence):

  iex> allowed_enum_values = ["Voirie", "Parking privé réservé à la clientèle"]
  iex> compute_constraint_enum_check(build_df("field", [nil, "", "   ", "  Voirie. "]), "field", allowed_enum_values) |> df_values(:check_field_constraint_enum)
  [nil, false, false, false]
  """
  def compute_constraint_enum_check(%Explorer.DataFrame{} = df, field, enum_values) do
    column_check_name = build_check_column_name(field, {:constraint, :enum})

    Explorer.DataFrame.mutate_with(df, fn df ->
      outcome = df[field] |> Explorer.Series.in(enum_values)
      %{column_check_name => outcome}
    end)
  end

  @supported_boolean_values ["true", "false"]

  @doc """
  Given a `type:  "boolean"` type specifier, compute a column asserting that the type is met.

  We only support `true` and `false`, not trying to massage any data here at this point.

  Valid cases:

  iex> compute_type_boolean_check(build_df("field", ["true", "false"]), "field") |> df_values(:check_field_type_boolean)
  [true, true]

  Invalid cases:

  iex> compute_type_boolean_check(build_df("field", [nil, "", "   ", "  true ", "VRAI", "FAUX", "1", "0"]), "field") |> df_values(:check_field_type_boolean)
  [nil, false, false, false, false, false, false, false]
  """
  def compute_type_boolean_check(%Explorer.DataFrame{} = df, field) do
    column_check_name = build_check_column_name(field, {:type, :boolean})

    Explorer.DataFrame.mutate_with(df, fn df ->
      outcome = df[field] |> Explorer.Series.in(@supported_boolean_values)
      %{column_check_name => outcome}
    end)
  end

  @doc """
  Given a `type:  "integer"` type specifier, compute a column asserting that the type is met.

  Valid cases:

  iex> compute_type_integer_check(build_df("field", ["8", "-4", "05"]), "field") |> df_values(:check_field_type_integer)
  [true, true, true]

  Invalid cases (note that the very large integer, overflowing the capacity, is marked as invalid):

  iex> compute_type_integer_check(build_df("field", [nil, "", "   ", "  8 ", "9999999999999999999999", "INF", "NaN"]), "field") |> df_values(:check_field_type_integer)
  [false, false, false, false, false, false, false]
  """
  def compute_type_integer_check(%Explorer.DataFrame{} = df, field) do
    column_check_name = build_check_column_name(field, {:type, :integer})

    Explorer.DataFrame.mutate_with(df, fn df ->
      outcome =
        df[field]
        |> Explorer.Series.cast(:integer)
        |> Explorer.Series.is_not_nil()

      %{column_check_name => outcome}
    end)
  end

  @doc """
  Given a `type: "number"` type specifier, compute a column asserting that the type is met.

  Ref:
  - https://specs.frictionlessdata.io/table-schema/#number

  We do not consider infinite / NaN values valid (unlike `TableSchema`).

  Valid cases:

  iex> compute_type_number_check(build_df("field", ["8", "-4", "05", "+5.47", "-9.789", "9999999999999999999999"]), "field") |> df_values(:check_field_type_number)
  [true, true, true, true, true, true]

  Invalid cases:

  iex> compute_type_number_check(build_df("field", [nil, "", "   ", "  8 ", "INF", "-INF", "NaN", "foobar"]), "field") |> df_values(:check_field_type_number)
  [false, false, false, false, false, false, false, false]
  """
  def compute_type_number_check(%Explorer.DataFrame{} = df, field) do
    column_check_name = build_check_column_name(field, {:type, :number})

    Explorer.DataFrame.mutate_with(df, fn df ->
      casted_field =
        df[field]
        |> Explorer.Series.cast({:f, 64})

      outcome =
        Explorer.Series.and(
          Explorer.Series.is_not_nil(casted_field),
          Explorer.Series.is_finite(casted_field)
        )

      %{column_check_name => outcome}
    end)
  end

  @doc """
  Given a numerical value (`integer` or `number` only) for type specifier, ensure that the value is greater than or equal to some minimum value.

  NOTE: overflow is not consistent with `integer` check here.

  Valid cases:

  iex> compute_constraint_minimum_check(build_df("field", ["8", "0", "05", "5.1", "0.0", "9999999999999999999999"]), "field", 0) |> df_values(:check_field_constraint_minimum)
  [true, true, true, true, true, true]

  Invalid cases (note the `nil` occurrences):

  iex> compute_constraint_minimum_check(build_df("field", [nil, "", "   ", "  8 ", "-4", "-5.2"]), "field", 0) |> df_values(:check_field_constraint_minimum)
  [nil, nil, nil, nil, false, false]
  """
  def compute_constraint_minimum_check(%Explorer.DataFrame{} = df, field, minimum) do
    column_check_name = build_check_column_name(field, {:constraint, :minimum})

    Explorer.DataFrame.mutate_with(df, fn df ->
      outcome =
        df[field]
        # NOTE: we use float check for both `integer` and `number`, for simplicity for now.
        |> Explorer.Series.cast({:f, 64})
        |> Explorer.Series.greater_equal(minimum)

      %{column_check_name => outcome}
    end)
  end

  @iso_date_pattern ~S/\A\d{4}\-\d{2}\-\d{2}\z/

  @doc """
  Ensure a date field matches the expected format. Allowed format is hardcoded to
  `%Y-%m-%d` since this is the only case we need.

  Ref comes from:
  - https://specs.frictionlessdata.io/table-schema/#date
  - https://docs.python.org/3/library/datetime.html#strftime-strptime-behavior

  Valid cases:

  iex> compute_format_date_check(build_df("field", ["2024-10-07"]), "field", "%Y-%m-%d") |> df_values(:check_field_format_date)
  [true]

  Invalid cases (note the `nil` occurrence):

  iex> compute_format_date_check(build_df("field", [nil, "", "   ", " 2024-10-07 ", "2024/10/07", "2024", "2024-10", "foobar"]), "field", "%Y-%m-%d") |> df_values(:check_field_format_date)
  [nil, false, false, false, false, false, false, false]
  """
  def compute_format_date_check(%Explorer.DataFrame{} = df, field, "%Y-%m-%d" = _format) do
    column_check_name = build_check_column_name(field, {:format, :date})

    Explorer.DataFrame.mutate_with(df, fn df ->
      outcome = df[field] |> Explorer.Series.re_contains(@iso_date_pattern)
      %{column_check_name => outcome}
    end)
  end

  # for now, use a regexp trying to catch proper lat/lon arrays,
  # because it's easier than splitting/verifying each sub-part using
  # Explorer primitives
  @geopoint_array_pattern ~S'\A\[\-?\d+(\.\d+)?,\s?\-?\d+(\.\d+)?\]\z'

  @doc """
  Ensure a geopoint column is of type array, and contains 2 valid floats.

  This does not actually verify that the coordinates make sense.

  Reference:
  - https://specs.frictionlessdata.io/table-schema/#geopoint

  Valid cases:

  iex> input_values = ["[1,2]", "[-3,4.5]", "[0.0, -0.99]", "[-123.456,789]", "[42, 0]"]
  iex> compute_type_geopoint_check(build_df("field", input_values), "field", "array") |> df_values(:check_field_type_geopoint)
  [true, true, true, true, true]

  Invalid cases:

  iex> input_values = ["1,2", "[1,2,3]", "[1;2]", "[1. ,2]", " [1,2]", "[a, b]", "[,]"]
  iex> compute_type_geopoint_check(build_df("field", input_values), "field", "array") |> df_values(:check_field_type_geopoint)
  [false, false, false, false, false, false, false]
  """
  def compute_type_geopoint_check(%Explorer.DataFrame{} = df, field, "array" = _format) do
    column_check_name = build_check_column_name(field, {:type, :geopoint})

    Explorer.DataFrame.mutate_with(df, fn df ->
      outcome = df[field] |> Explorer.Series.re_contains(@geopoint_array_pattern)
      %{column_check_name => outcome}
    end)
  end
end
