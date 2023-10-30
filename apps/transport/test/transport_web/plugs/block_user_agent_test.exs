defmodule TransportWeb.Plugs.BlockUserAgentTest do
  use TransportWeb.ConnCase, async: true

  describe "init" do
    test "with strings" do
      assert [block_user_agent_keywords: [], log_user_agent: true] ==
               TransportWeb.Plugs.BlockUserAgent.init(log_user_agent: "true", block_user_agent_keywords: "")

      assert [block_user_agent_keywords: ["foo", "bar"], log_user_agent: false] ==
               TransportWeb.Plugs.BlockUserAgent.init(log_user_agent: "", block_user_agent_keywords: "foo|bar")
    end

    test "with keywords" do
      assert [log_user_agent: false, block_user_agent_keywords: ["foo", "bar"]] =
               TransportWeb.Plugs.BlockUserAgent.init(block_user_agent_keywords: ["foo", "bar"], log_user_agent: false)
    end
  end

  describe "call" do
    test "blocks the request if the user-agent matches", %{conn: conn} do
      text =
        conn
        |> Plug.Conn.put_req_header("user-agent", "Mozilla FooBar")
        |> TransportWeb.Plugs.BlockUserAgent.call(log_user_agent: false, block_user_agent_keywords: ["FooBar"])
        |> text_response(401)

      assert text == "Unauthorized"
    end

    test "does nothing if the user-agent does not match", %{conn: conn} do
      assert %Plug.Conn{halted: false} =
               conn
               |> Plug.Conn.put_req_header("user-agent", "Mozilla FooBar")
               |> TransportWeb.Plugs.BlockUserAgent.call(log_user_agent: false, block_user_agent_keywords: ["nope"])
    end
  end
end
