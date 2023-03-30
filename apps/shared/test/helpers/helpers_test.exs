defmodule Helpers.HelpersTest do
  use ExUnit.Case
  doctest Helpers, import: true

  test "last_updated" do
    assert nil == Helpers.last_updated([])

    assert "2023-01-15T05:33:47Z" ==
             Helpers.last_updated([
               %DB.Resource{last_update: ~U[2023-01-15 05:33:47Z]},
               %DB.Resource{last_update: ~U[2022-03-30 05:33:47Z]}
             ])
  end
end
