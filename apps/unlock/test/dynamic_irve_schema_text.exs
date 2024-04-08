defmodule Unlock.DynamicIRVESchemaTest do
  use ExUnit.Case, async: false
  doctest Checker

  test "experimental" do
    Unlock.DynamicIRVESchema.schema_content()
    |> get_in(["fields"])
    |> IO.inspect(IEx.inspect_opts())
  end
end
