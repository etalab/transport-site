defmodule Transport.ApplicationTest do
  use ExUnit.Case, async: false
  alias Transport.Application

  test "parse mongodb uri" do
    assert %{username: nil,
             password: nil,
             database: nil,
             hostname: nil,
             port: nil,
             pool: DBConnection.Poolboy,
             name: :mongo
             } == Application.parse_mongodb_uri("mongodb:///")
                  |> Map.new()

    assert %{username: "user",
             password: "pass",
             database: "database",
             hostname: "localhost",
             port: 666,
             pool: DBConnection.Poolboy,
             name: :mongo
             } == Application.parse_mongodb_uri("mongodb://user:pass@localhost:666/database")
                  |> Map.new()

  end
end
