defmodule Transport.DataValidator.ServerTest do
  use ExUnit.Case, async: true
  alias Transport.DataValidator.Server

  test "publish a message" do
    assert {:ok, _} = Server.validate_data("pouet")
  end
end
