defmodule TransportWeb.Plugs.RateLimiterTest do
  use TransportWeb.ConnCase, async: false
  alias TransportWeb.Plugs.RateLimiter

  setup do
    System.put_env(
      envs = [
        {"LOG_USER_AGENT", "true"},
        {"BLOCK_USER_AGENT_KEYWORDS", "Foo|Bar"},
        {"ALLOW_USER_AGENTS", "SpecialUserAgent"}
      ]
    )

    on_exit(fn ->
      Enum.each(envs, fn {env_name, _} -> System.delete_env(env_name) end)
    end)
  end

  doctest RateLimiter, import: true

  describe "init" do
    test "with strings" do
      assert [allow_user_agents: [], block_user_agent_keywords: [], log_user_agent: true] =
               RateLimiter.init(
                 log_user_agent: "true",
                 block_user_agent_keywords: "",
                 allow_user_agents: ""
               )

      assert [
               allow_user_agents: ["bar", "baz"],
               block_user_agent_keywords: ["foo", "bar"],
               log_user_agent: false
             ] =
               RateLimiter.init(
                 log_user_agent: "",
                 block_user_agent_keywords: "foo|bar",
                 allow_user_agents: "bar|baz"
               )
    end

    test "with keywords" do
      assert [
               allow_user_agents: [],
               log_user_agent: false,
               block_user_agent_keywords: ["foo", "bar"]
             ] ==
               RateLimiter.init(
                 block_user_agent_keywords: ["foo", "bar"],
                 log_user_agent: false,
                 allow_user_agents: []
               )
    end

    test "use env variables" do
      assert :use_env_variables = RateLimiter.init(:use_env_variables)
    end
  end

  describe "call" do
    test "blocks the request if the user-agent matches", %{conn: conn} do
      text =
        conn
        |> Plug.Conn.put_req_header("user-agent", "Mozilla FooBar")
        |> RateLimiter.call(
          log_user_agent: false,
          block_user_agent_keywords: ["FooBar"],
          allow_user_agents: []
        )
        |> text_response(401)

      assert text == "Unauthorized"
    end

    test "does nothing if the user-agent does not match", %{conn: conn} do
      assert %Plug.Conn{halted: false} =
               conn
               |> Plug.Conn.put_req_header("user-agent", "Mozilla FooBar")
               |> RateLimiter.call(
                 log_user_agent: false,
                 block_user_agent_keywords: ["nope"],
                 allow_user_agents: []
               )
    end

    test "with environment variables", %{conn: conn} do
      assert "Foo|Bar" == System.get_env("BLOCK_USER_AGENT_KEYWORDS")

      text =
        conn
        |> Plug.Conn.put_req_header("user-agent", "Mozilla Foo")
        |> RateLimiter.call(:use_env_variables)
        |> text_response(401)

      assert text == "Unauthorized"
    end

    test "with environment variables, homepage", %{conn: conn} do
      assert "Foo|Bar" == System.get_env("BLOCK_USER_AGENT_KEYWORDS")

      text =
        conn
        |> Plug.Conn.put_req_header("user-agent", "Mozilla Bar")
        |> get(~p"/")
        |> text_response(401)

      assert text == "Unauthorized"
    end

    test "does not crash when user-agent is not set", %{conn: conn} do
      assert [] == get_req_header(conn, "user-agent")

      assert %Plug.Conn{halted: false} =
               conn
               |> RateLimiter.call(
                 log_user_agent: true,
                 block_user_agent_keywords: [],
                 allow_user_agents: []
               )
    end

    test "blocks a request if IP is blocked", %{conn: conn} do
      [blocked_ip] = Application.fetch_env!(:phoenix_ddos, :blocklist_ips)

      assert %Plug.Conn{status: 429} =
               conn
               |> Plug.Conn.put_req_header("x-forwarded-for", to_string(blocked_ip))
               |> get(~p"/")
    end

    test "does not block a request if user agent is allowed, even if IP is blocked", %{conn: conn} do
      [blocked_ip] = Application.fetch_env!(:phoenix_ddos, :blocklist_ips)
      assert "SpecialUserAgent" == System.get_env("ALLOW_USER_AGENTS")

      conn
      |> Plug.Conn.put_req_header("x-forwarded-for", to_string(blocked_ip))
      |> Plug.Conn.put_req_header("user-agent", "SpecialUserAgent")
      |> get(~p"/robots.txt")
      |> text_response(200)
    end
  end
end
