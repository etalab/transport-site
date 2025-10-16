defmodule Transport.IRVE.Validation.PrimitivesTest do
  use ExUnit.Case, async: true

  def build_df(field, values) do
    Explorer.DataFrame.new(%{field => values})
  end

  def df_values(df, field) do
    Explorer.DataFrame.to_columns(df, atom_keys: true)
    |> Map.fetch!(field)
  end

  doctest Transport.IRVE.Validation.Primitives, import: true
end
