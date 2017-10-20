defmodule Transport.DataValidator.ServerTest do
  use ExUnit.Case, async: false
  alias Transport.DataValidator.Server

  setup do
    :ok = Server.subscribe()
  end

  test "publish a message" do
    assert :ok = Server.validate_data("pouet")
    assert_receive {:ok, %{publish: "pouet"}}
  end
end
