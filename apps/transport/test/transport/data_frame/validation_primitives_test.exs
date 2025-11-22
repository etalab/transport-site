defmodule Transport.DataFrame.Validation.PrimitivesTest do
  use ExUnit.Case, async: true

  alias Explorer.Series

  def build_series(values) do
    Series.from_list(values)
  end

  doctest Transport.DataFrame.Validation.Primitives, import: true
end
