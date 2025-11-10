defmodule Transport.IRVE.Validation.PrimitivesTest do
  use ExUnit.Case, async: true

  alias Explorer.Series

  def build_series(values) do
    Series.from_list(values)
  end

  doctest Transport.IRVE.Validation.Primitives, import: true
end
