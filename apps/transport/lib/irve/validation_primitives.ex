defmodule Transport.IRVE.Validation.Primitives do
  @moduledoc """
  Extracted from real-life use, a set of primitives allowing us
  to implement a full Explorer-backed validator for the IRVE static schema
  (or other schemas if needed).

  TODOs:
  - Decouple mutation computation, from its injection via `mutate_with` & target field name computation.
  - Add a safe-guard to automatically raise at the same time, to protect us from involuntarily check overwrites.
  - Make a clear-cut choice weither we should strip values from leading/trailing spaces during validation, or
    via pre-processing, or even not at all (strict mode), like I understand the current `TableSchema` IRVE setup.
  - Standardize the way we handle computations for nil / missing values
  - Compare things a bit with validata (in terms of computations)
  """

  @doc """
  Given a `required: xyz` field, computes a column asserting that the check passes.

  If `required: true` is passed, the value must be provided (not nil, nor an empty string). 
  For each row, the column will equate `true` if the criteria is matched, otherwise `false`. 

  iex> compute_required_check(build_df("field", [nil, "   ", " something "]), "field", true) |> df_values(:check_field_required)
  [false, false, true]

  If `required: false` is passed, the colum will equate `nil`, to advertise that the check
  has not been actually evaluated.

  iex> compute_required_check(build_df("field", [nil, "   ", " something "]), "field", false) |> df_values(:check_field_required)
  [nil, nil, nil]
  """
  def compute_required_check(%Explorer.DataFrame{} = df, field, is_required?) when is_boolean(is_required?) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      check_name = "check_#{field}_required"

      outcome =
        case is_required? do
          true ->
            df[field]
            |> Explorer.Series.strip()
            |> Explorer.Series.fill_missing("")
            |> Explorer.Series.not_equal("")

          false ->
            nil
        end

      %{
        check_name => outcome
      }
    end)
  end

  @doc """
  Given a `pattern: xyz` constraint, computes a column asserting that the regexp is respected.

  Only one pattern per field is allowed. No stripping is achieved.

  TODO: verify compliance on `id_station_itinerance` pattern, directly from the doctests.
  TODO: same for "horaires" pattern

  iex> compute_pattern_constraint_check(build_df("field", [nil, "   ", " something ", "123456789"]), "field", ~S/^\\d{9}$/) |> df_values(:check_field_constraint_pattern)
  [nil, false, false, true]
  """
  def compute_pattern_constraint_check(%Explorer.DataFrame{} = df, field, pattern) when is_binary(pattern) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      check_name = "check_#{field}_constraint_pattern"

      outcome =
        df[field]
        |> Explorer.Series.re_contains(pattern)

      %{
        check_name => outcome
      }
    end)
  end

  # NOTE: this is _not_ an Elixir regex, but a string containing a pattern compiled
  # to a regex by Explorer/the Polars crate.
  # NOTE: a fully compliant email regexp is a beast, not found in the Elixir stdlib, so
  # going with something simple for now.
  @simple_email_pattern ~S/(?i)\A^[\w+\.\-]+@[\w+\.\-]+\z/

  @doc """
  Given a `format: "email"` field specifier, compute a column asserting that the format is fulfilled.

  NOTE: may rename the method to allow passing the format (e.g. "email") as a parameter instead later,
  depending on cases I'm facing.

  iex> compute_format_email_check(build_df("field", [nil, "   ", "hello@example.com"]), "field") |> df_values(:check_field_email_format)
  [nil, false, true]
  """
  def compute_format_email_check(%Explorer.DataFrame{} = df, field) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      check_name = "check_#{field}_email_format"

      outcome =
        df[field]
        |> Explorer.Series.re_contains(@simple_email_pattern)

      %{
        check_name => outcome
      }
    end)
  end

  @doc """
  Given a `enum: [a,b,c]` constraint specifier, compute a column asserting that the constraint is fulfilled.

  iex> input_values = [nil, "", "   ", "  Voirie. ", "Voirie"]
  iex> allowed_enum_values = ["Voirie", "Parking privé réservé à la clientèle"]
  iex> compute_constraint_enum_check(build_df("field", input_values), "field", allowed_enum_values) |> df_values(:check_field_enum_constraint)
  [nil, false, false, false, true]
  """
  def compute_constraint_enum_check(%Explorer.DataFrame{} = df, field, enum_values) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      check_name = "check_#{field}_enum_constraint"

      outcome =
        df[field]
        |> Explorer.Series.in(enum_values)

      %{
        check_name => outcome
      }
    end)
  end

  @supported_boolean_values ["true", "false"]

  @doc """
  Given a `type:  "boolean"` type specifier, compute a column asserting that the type is met.

  iex> input_values = [nil, "", "   ", "  true ", "true", "false","VRAI","FAUX", "1", "0"]
  iex> compute_type_boolean_check(build_df("field", input_values), "field") |> df_values(:check_field_boolean_type)
  [nil, false, false, false, true, true, false, false, false, false]
  """
  def compute_type_boolean_check(%Explorer.DataFrame{} = df, field) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      check_name = "check_#{field}_boolean_type"

      outcome =
        df[field]
        |> Explorer.Series.in(@supported_boolean_values)

      %{
        check_name => outcome
      }
    end)
  end

  @doc """
  Given a `type:  "integer"` type specifier, compute a column asserting that the type is met.

  iex> input_values = [nil, "", "   ", "  8 ", "8", "-4","05","9999999999999999999999", "INF", "NaN"]
  iex> compute_type_integer_check(build_df("field", input_values), "field") |> df_values(:check_field_integer_type)
  [false, false, false, false, true, true, true, false, false, false]
  """
  def compute_type_integer_check(%Explorer.DataFrame{} = df, field) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      check_name = "check_#{field}_integer_type"

      outcome =
        df[field]
        |> Explorer.Series.cast(:integer)
        |> Explorer.Series.is_not_nil()

      %{
        check_name => outcome
      }
    end)
  end

  @doc """
  Given a `type: "number"` type specifier, compute a column asserting that the type is met.

  Ref:
  - https://specs.frictionlessdata.io/table-schema/#types-and-formats

  We do not consider infinite / NaN values valid.

  iex> input_values = [nil, "", "   ", "  8 ", "8", "-4","05","+5.47","-9.789", "INF", "-INF", "NaN", "9999999999999999999999", "foobar"]
  iex> compute_type_number_check(build_df("field", input_values), "field") |> df_values(:check_field_number_type)
  [false, false, false, false, true, true, true, true, true, false, false, false, true,false]
  """
  def compute_type_number_check(%Explorer.DataFrame{} = df, field) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      check_name = "check_#{field}_number_type"

      field =
        df[field]
        |> Explorer.Series.cast({:f, 64})

      outcome =
        Explorer.Series.and(
          Explorer.Series.is_not_nil(field),
          Explorer.Series.is_finite(field)
        )

      %{
        check_name => outcome
      }
    end)
  end

  @doc """
  Given a numerical value (`integer` or `number` only) for type specifier, ensure that the value is greater than some minimum value.

  NOTE: overflow is not consistent with `integer` check here

  iex> input_values = [nil, "", "   ", "  8 ", "8", "-4","0", "05", "5.1", "-5.2", "0.0", "9999999999999999999999"]
  iex> compute_constraint_minimum_check(build_df("field", input_values), "field", 0) |> df_values(:check_field_constraint_minimum)
  [nil, nil, nil, nil, true, false, true, true, true, false, true, true]
  """
  def compute_constraint_minimum_check(%Explorer.DataFrame{} = df, field, minimum) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      check_name = "check_#{field}_constraint_minimum"

      outcome =
        df[field]
        # NOTE: we use float check for both `integer` and `number`, for simplicity for now.
        |> Explorer.Series.cast({:f, 64})
        |> Explorer.Series.greater_equal(minimum)

      %{
        check_name => outcome
      }
    end)
  end

  @iso_date_pattern ~S/\A\d{4}\-\d{2}\-\d{2}\z/

  @doc """
  Ensure a date field matches the expected format. Allowed format is hardcoded to
  `%Y-%m-%d` since this is the only case we need.

  Ref comes from:
  - https://specs.frictionlessdata.io/table-schema/#types-and-formats
  - https://docs.python.org/3/library/datetime.html#strftime-strptime-behavior

  iex> input_values = [nil, "", "   ", " 2024-10-07 ", "2024-10-07", "2024/10/07", "2024", "2024-10"]
  iex> compute_format_date_check(build_df("field", input_values), "field", "%Y-%m-%d") |> df_values(:check_field_format_date)
  [nil, false, false, false, true, false, false, false]
  """
  def compute_format_date_check(%Explorer.DataFrame{} = df, field, "%Y-%m-%d" = _format) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      check_name = "check_#{field}_format_date"

      outcome =
        df[field]
        |> Explorer.Series.re_contains(@iso_date_pattern)

      %{
        check_name => outcome
      }
    end)
  end

  # for now, use a regexp trying to catch proper lat/lon arrays
  @geopoint_array_pattern ~S'\A\[\-?\d+(\.\d+)?,\s?\-?\d+(\.\d+)?\]\z'

  @doc """
  Ensure a geopoint column is of type array, and contains 2 valid floats.

  Reference:
  - https://specs.frictionlessdata.io/table-schema/#geopoint

  Valid cases:

  iex> input_values = ["[1,2]", "[-3,4.5]", "[0.0, -0.99]", "[-123.456,789]", "[42, 0]"]
  iex> compute_type_geopoint_check(build_df("field", input_values), "field", "array") |> df_values(:check_field_format_geopoint)
  [true, true, true, true, true]

  Invalid cases:

  iex> input_values = ["1,2", "[1,2,3]", "[1;2]", "[1. ,2]", " [1,2]", "[a, b]", "[,]"]
  iex> compute_type_geopoint_check(build_df("field", input_values), "field", "array") |> df_values(:check_field_format_geopoint)
  [false, false, false, false, false, false, false]
  """
  def compute_type_geopoint_check(%Explorer.DataFrame{} = df, field, "array" = _format) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      check_name = "check_#{field}_format_geopoint"

      outcome =
        df[field]
        |> Explorer.Series.re_contains(@geopoint_array_pattern)

      %{
        check_name => outcome
      }
    end)
  end
end
