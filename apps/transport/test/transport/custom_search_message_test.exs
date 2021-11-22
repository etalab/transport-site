defmodule Transport.CustomSearchMessageTest do
  use ExUnit.Case, async: true
  doctest Transport.CustomSearchMessage

  defp space_shuttle do
    %{
      "category" => "space-shuttle",
      "search_params" => [%{"key" => "type", "value" => "space-shuttle"}],
      "msg" => %{
        "fr" => "L'ouverture des données est en cours."
      }
    }
  end

  defp teleportation do
    %{
      "category" => "teleportation",
      "search_params" => [%{"key" => "type", "value" => "teleportation"}, %{"key" => "filter", "value" => "real_time"}],
      "msg" => %{
        "fr" => "Ne bougez pas."
      }
    }
  end

  defp jetski do
    %{
      "category" => "jetski",
      "search_params" => [%{"key" => "modes", "value" => ["jetski"]}, %{"key" => "type", "value" => "boat"}],
      "msg" => %{
        "fr" => "accrochez vous",
        "en" => "hold on"
      }
    }
  end

  test "all messages have a french AND an english content" do
    Transport.CustomSearchMessage.get_messages()
    |> Enum.each(fn %{"msg" => msg, "category" => category} ->
      assert is_binary(msg["fr"]), "fr message is missing for category #{category}"
      assert is_binary(msg["en"]), "en message is missing for category #{category}"
    end)
  end

  test "find a category for a simple query" do
    messages = [space_shuttle(), teleportation()]
    locale = "fr"

    msg =
      Transport.CustomSearchMessage.filter_messages(
        messages,
        %{"type" => "teleportation", "filter" => "real_time"},
        locale
      )

    assert msg == "Ne bougez pas."
  end

  test "no matching category" do
    messages = [space_shuttle(), teleportation()]
    locale = "fr"

    msg =
      Transport.CustomSearchMessage.filter_messages(
        messages,
        %{"type" => "boat"},
        locale
      )

    assert is_nil(msg)
  end

  test "query special case with array, fetch english message" do
    messages = [space_shuttle(), jetski()]
    locale = "en"

    msg =
      Transport.CustomSearchMessage.filter_messages(
        messages,
        %{"type" => "boat", "modes" => ["jetski"]},
        locale
      )

    assert msg == "hold on"
  end
end
