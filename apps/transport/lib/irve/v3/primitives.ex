defmodule Transport.IRVE.V3.Primitives do
  @moduledoc """
  Series-based primitives needed by the v3 validator on top of `Transport.DataFrame.Validation.Primitives`,
  with the same conventions: a series of strings in, a boolean series out.
  """

  alias Explorer.Series

  @doc """
  Checks that values match a Table Schema `pattern`, which applies to the whole value:

      iex> full_match(Series.from_list(["ab", "xab"]), "a|ab") |> Series.to_list()
      [true, false]
  """
  def full_match(series, pattern) when is_binary(pattern) do
    Series.re_contains(series, "\\A(?:" <> pattern <> ")\\z")
  end

  @doc """
  Checks that numeric values are lower than or equal to a maximum (`nil` for non-numeric values).

      iex> is_less_or_equal(Series.from_list(["90", "90.1", "abc"]), 90) |> Series.to_list()
      [true, false, nil]
  """
  def is_less_or_equal(series, maximum) when is_number(maximum) do
    series
    |> Series.cast({:f, 64})
    |> Series.less_equal(maximum)
  end

  @utc_datetime_pattern ~S/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/

  @doc """
  Checks that values are real UTC datetimes, in the only format used by the v3 schemas.

      iex> datetime?(Series.from_list(["2024-12-17T13:13:31Z", "2024-02-30T13:13:31Z", "2024-12-17T13:13:31", "2024-12-17T13:13:31+01:00"]), "%Y-%m-%dT%H:%M:%SZ") |> Series.to_list()
      [true, false, false, false]
  """
  def datetime?(series, "%Y-%m-%dT%H:%M:%SZ" = format) do
    Series.and(
      Series.re_contains(series, @utc_datetime_pattern),
      series |> Series.strptime(format) |> Series.is_not_nil()
    )
  end
end
