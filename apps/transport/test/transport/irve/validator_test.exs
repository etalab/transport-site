defmodule Transport.IRVE.ValidatorTest do
  use ExUnit.Case, async: true

  test "the test" do
    Transport.IRVE.Validator.validate_file("some_file.csv")
  end
end
