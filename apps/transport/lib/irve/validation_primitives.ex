defmodule Transport.IRVE.Validation.Primitives do
  @moduledoc """
  Extracted from real-life use, a set of primitives allowing us
  to implement a full Explorer-backed validator for the IRVE static schema
  (or other schemas if needed).

  TODOs:
  - Decouple mutation computation, from its injection via `mutate_with` & target field name computation.
  - Add a safe-guard to automatically raise at the same time, to protect us from involuntarily check overwrites.
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
end
