defmodule DbTest do
  use ExUnit.Case
  doctest Db

  test "greets the world" do
    assert Db.hello() == :world
  end
end
