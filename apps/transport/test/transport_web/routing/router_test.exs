defmodule TransportWeb.Routing.RouterTest do
  use ExUnit.Case, async: true
  doctest TransportWeb.Router, import: true

  test "static_paths documents and files exist" do
    assert "../../apps/transport/priv/static/*"
           |> Path.wildcard()
           |> Enum.map(&Path.basename/1)
           |> MapSet.new() == TransportWeb.static_paths() |> MapSet.new()
  end
end
