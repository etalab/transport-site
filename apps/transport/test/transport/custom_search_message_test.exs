defmodule Transport.CustomSearchMessageTest do
  use ExUnit.Case, async: true
  doctest Transport.CustomSearchMessage

  test "all messages have a french AND an english content" do
    Transport.CustomSearchMessage.get_messages()
    |> Enum.each(fn %{"msg" => msg} ->
      assert is_binary(msg["fr"])
      assert is_binary(msg["en"])
    end)
  end
end
