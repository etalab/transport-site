defmodule TransportWeb.Plugs.BlockUserAgentTest do
  use TransportWeb.ConnCase, async: false

  setup do
    System.put_env(
      envs = [
        {"LOG_USER_AGENT", "true"},
        {"BLOCK_USER_AGENT_KEYWORDS", "Foo|Bar"}
      ]
    )

    on_exit(fn ->
      Enum.each(envs, fn {env_name, _} -> System.delete_env(env_name) end)
    end)
  end

  doctest TransportWeb.Plugs.BlockUserAgent, import: true

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

    test "use env variables" do
      assert :use_env_variables = TransportWeb.Plugs.BlockUserAgent.init(:use_env_variables)
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

    test "with environment variables", %{conn: conn} do
      assert "Foo|Bar" == System.get_env("BLOCK_USER_AGENT_KEYWORDS")

      text =
        conn
        |> Plug.Conn.put_req_header("user-agent", "Mozilla Foo")
        |> TransportWeb.Plugs.BlockUserAgent.call(:use_env_variables)
        |> text_response(401)

      assert text == "Unauthorized"
    end

    test "with environment variables, homepage", %{conn: conn} do
      assert "Foo|Bar" == System.get_env("BLOCK_USER_AGENT_KEYWORDS")

      text =
        conn
        |> Plug.Conn.put_req_header("user-agent", "Mozilla Bar")
        |> get("/")
        |> text_response(401)

      assert text == "Unauthorized"
    end

    test "does not crash when user-agent is not set", %{conn: conn} do
      assert [] == get_req_header(conn, "user-agent")

      assert %Plug.Conn{halted: false} =
               conn
               |> TransportWeb.Plugs.BlockUserAgent.call(log_user_agent: true, block_user_agent_keywords: [])
    end
  end
end
