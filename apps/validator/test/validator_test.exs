defmodule ValidatorTest do
  use ExUnit.Case
  doctest Validator

  test "greets the world" do
    assert Validator.hello() == :world
  end
end
