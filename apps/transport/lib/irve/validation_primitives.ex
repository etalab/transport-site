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

  iex> compute_check(build_df("field", [nil, "   ", " something "]), "field", :required, true) |> df_values(:check_field_required_true)
  [false, false, true]

  If `required: false` is passed, the colum will equate `nil`, to advertise that the check
  has not been actually evaluated.

  iex> compute_check(build_df("field", [nil, "   ", " something "]), "field", :required, false) |> df_values(:check_field_required_false)
  [nil, nil, nil]
  """
  def compute_check(%Explorer.DataFrame{} = df, field, :required, is_required?) when is_boolean(is_required?) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      check_name = "check_#{field}_required_#{is_required?}"

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
end
