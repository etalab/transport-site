defmodule Transport.DataFrame.Validation.Primitives do
  @moduledoc """
  Series-based validation primitives.

  Each function takes an `Explorer.Series` and returns a boolean `Explorer.Series`
  indicating whether each value passes validation.

  ## Philosophy

  - **Input**: A series of string values (as read from CSV)
  - **Output**: A boolean series indicating validity
  - **No side effects**: Pure functions that don't modify input
  - **Composable**: Can be combined with other series operations

  ## Whitespace & optionality handling

  The checks implemented here assume that:
  - Heading & trailing whitespaces have been removed during a preprocessing step
  - Optionality of the value is handled at an upper level

  ## Examples

      iex> alias Explorer.Series
      iex> series = Series.from_list(["hello@example.com", "invalid", nil])
      iex> email?(series) |> Series.to_list()
      [true, false, nil]
  """

  alias Explorer.Series

  @doc """
  Check if values are present (non-nil and non-empty after preprocessing has stripped whitespace).

  ## Examples

      iex> has_value(build_series(["something", nil])) |> Series.to_list()
      [true, false]

      iex> has_value(build_series(["hello", ""])) |> Series.to_list()
      [true, false]
  """
  def has_value(series) do
    Series.and(
      Series.is_not_nil(series),
      Series.not_equal(series, "")
    )
  end

  @doc """
  Check if values match a given regex pattern (provided as string, as expected by Explorer).

  ## Examples

      iex> is_matching_the_pattern(build_series(["123456789", "12345678"]), ~S/^\\d{9}$/) |> Series.to_list()
      [true, false]

      iex> is_matching_the_pattern(build_series(["abc", "123"]), ~S/^\\d+$/) |> Series.to_list()
      [false, true]
  """
  def is_matching_the_pattern(series, pattern) when is_binary(pattern) do
    Series.re_contains(series, pattern)
  end

  @simple_email_pattern ~S/(?i)\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  @doc """
  Get the simple email validation pattern.

  Returns a regex pattern string compatible with Explorer/Polars.
  """
  def simple_email_pattern, do: @simple_email_pattern

  @doc """
  Check if values are valid email addresses.

  Uses a simple email pattern that catches most common cases.

  ## Examples

      iex> email?(build_series(["hello@example.com", "invalid"])) |> Series.to_list()
      [true, false]

      iex> email?(build_series(["test@foo.bar", "hello@fool"])) |> Series.to_list()
      [true, false]
  """
  def email?(series) do
    Series.re_contains(series, @simple_email_pattern)
  end

  @doc """
  Check if values are in a given list of allowed values (enum).

  ## Examples

      iex> is_in_enum(build_series(["Voirie", "Invalid"]), ["Voirie", "Parking"]) |> Series.to_list()
      [true, false]

      iex> is_in_enum(build_series(["A", "B", "C"]), ["A", "B"]) |> Series.to_list()
      [true, true, false]
  """
  def is_in_enum(series, allowed_values) when is_list(allowed_values) do
    Series.in(series, allowed_values)
  end

  @supported_boolean_values ["true", "false"]

  @doc """
  Check if values are valid booleans ("true" or "false" strings).

  Only accepts the exact strings "true" and "false", no other representations.

  ## Examples

      iex> boolean_value?(build_series(["true", "false", "TRUE"])) |> Series.to_list()
      [true, true, false]

      iex> boolean_value?(build_series(["1", "0", "VRAI", "FAUX"])) |> Series.to_list()
      [false, false, false, false]
  """
  def boolean_value?(series) do
    Series.in(series, @supported_boolean_values)
  end

  @doc """
  Check if values are valid integers.

  Attempts to cast to integer and checks for successful cast.
  Overflow values are considered invalid.

  ## Examples

      iex> integer_value?(build_series(["8", "-4", "05"])) |> Series.to_list()
      [true, true, true]

      iex> integer_value?(build_series(["9999999999999999999999", "INF", "NaN"])) |> Series.to_list()
      [false, false, false]
  """
  def integer_value?(series) do
    series
    |> Series.cast(:integer)
    |> Series.is_not_nil()
  end

  @doc """
  Check if values are valid numbers (floats).

  Casts to float and checks for finite values (excludes Inf and NaN).

  ## Examples

      iex> numeric?(build_series(["8", "-4.5", "05", "+5.47", "-9.789"])) |> Series.to_list()
      [true, true, true, true, true]

      iex> numeric?(build_series(["INF", "-INF", "NaN", "foobar"])) |> Series.to_list()
      [false, false, false, false]

      iex> numeric?(build_series(["9999999999999999999999"])) |> Series.to_list()
      [true]
  """
  def numeric?(series) do
    casted = Series.cast(series, {:f, 64})

    Series.and(
      Series.is_not_nil(casted),
      Series.is_finite(casted)
    )
  end

  @doc """
  Check if numeric values are greater than or equal to a minimum.

  Casts to float for comparison. Returns nil for non-numeric values.

  ## Examples

      iex> is_greater_or_equal(build_series(["8", "0", "5.1", "0.0"]), 0) |> Series.to_list()
      [true, true, true, true]

      iex> is_greater_or_equal(build_series(["-4", "-5.2"]), 0) |> Series.to_list()
      [false, false]

      iex> is_greater_or_equal(build_series(["9999999999999999999999"]), 0) |> Series.to_list()
      [true]
  """
  def is_greater_or_equal(series, minimum) when is_number(minimum) do
    series
    |> Series.cast({:f, 64})
    |> Series.greater_equal(minimum)
  end

  @iso_date_pattern ~S/\A\d{4}\-\d{2}\-\d{2}\z/

  @doc """
  Check if values match ISO date format (YYYY-MM-DD) and represent real dates.

  The validation first ensures the pattern matches, then relies on the Explorer
  date casting to reject impossible dates (e.g., 2024-02-30).

  ## Examples

      iex> date?(build_series(["2024-10-07"]), "%Y-%m-%d") |> Series.to_list()
      [true]

      iex> date?(build_series(["2024-02-30", "2024/10/07", "2024", "2024-10", "foobar"]), "%Y-%m-%d") |> Series.to_list()
      [false, false, false, false, false]
  """
  def date?(series, "%Y-%m-%d" = _format) do
    matches_pattern = Series.re_contains(series, @iso_date_pattern)
    casted = Series.cast(series, :date)

    Series.and(
      matches_pattern,
      Series.is_not_nil(casted)
    )
  end

  @geopoint_array_pattern ~S/\A\[\-?\d+(\.\d+)?\s?,\s?\-?\d+(\.\d+)?\]\z/

  @doc """
  Check if values are valid geopoint arrays (TableSchema format).

  Expects format like "[lat,lon]" with numeric coordinates.
  Does not validate coordinate ranges.

  This validation follows the TableSchema specification for geopoint type.

  ## Examples

      iex> geopoint?(build_series(["[1,2]", "[-3,4.5]", "[0.0, -0.99]", "[-123.456,789]", "[42, 0]", "[1.2 , 3.4]"]), "array") |> Series.to_list()
      [true, true, true, true, true, true]

      iex> geopoint?(build_series(["1,2", "[1,2,3]", "[1;2]", "[1. ,2]", "[a, b]", "[,]"]), "array") |> Series.to_list()
      [false, false, false, false, false, false]
  """
  def geopoint?(series, "array" = _format) do
    Series.re_contains(series, @geopoint_array_pattern)
  end
end
