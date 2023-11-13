defmodule TransportWeb.Plugs.RateLimiter do
  @moduledoc """
  A Plug wrapper around [phoenix_ddos](https://github.com/xward/phoenix_ddos/) to:
  - log the User-Agent making an HTTP request
  - block HTTP requests when certain keywords are found in the User-Agent HTTP header
  - bypass the `phoenix_ddos` rate limiter for some HTTP User-Agents

  Options:
  - log_user_agent: boolean or string
  - block_user_agent_keywords: list of keywords or string that will be split on `|`
  - allow_user_agents: list of strings that will be split on `|`

  If the plug is configured with a magic value, `:use_env_variables`, the
  `call/2` method will be configured at runtime using environment variables.
  - LOG_USER_AGENT
  - BLOCK_USER_AGENT_KEYWORDS
  - ALLOW_USER_AGENTS
  """
  require Logger
  import Plug.Conn
  @behaviour Plug

  @impl true
  def init(:use_env_variables), do: :use_env_variables

  def init(
        log_user_agent: log_user_agent,
        block_user_agent_keywords: block_user_agent_keywords,
        allow_user_agents: allow_user_agents
      )
      when is_binary(log_user_agent) and is_binary(block_user_agent_keywords) and is_binary(allow_user_agents) do
    init(
      log_user_agent: log_user_agent == "true",
      block_user_agent_keywords: prepare_param(block_user_agent_keywords),
      allow_user_agents: prepare_param(allow_user_agents)
    )
  end

  def init(options) do
    Keyword.validate!(options, log_user_agent: false, block_user_agent_keywords: [], allow_user_agents: [])
  end

  @doc """
  iex> prepare_param("")
  []
  iex> prepare_param("foo|bar")
  ["foo", "bar"]
  """
  @spec prepare_param(binary()) :: [binary()]
  def prepare_param(""), do: []
  def prepare_param(value) when is_binary(value), do: String.split(value, "|")

  @impl true
  def call(%Plug.Conn{} = conn, :use_env_variables) do
    options =
      init(
        log_user_agent: System.get_env("LOG_USER_AGENT", "false"),
        block_user_agent_keywords: System.get_env("BLOCK_USER_AGENT_KEYWORDS", ""),
        allow_user_agents: System.get_env("ALLOW_USER_AGENTS", "")
      )

    call(conn, options)
  end

  def call(%Plug.Conn{} = conn, options) do
    conn
    |> maybe_log_http_details(Keyword.fetch!(options, :log_user_agent))
    |> maybe_block_request(Keyword.fetch!(options, :block_user_agent_keywords))
    |> maybe_allow_user_agent(Keyword.fetch!(options, :allow_user_agents))
  end

  defp maybe_log_http_details(%Plug.Conn{method: method, request_path: request_path} = conn, true = _log_user_agent) do
    user_agent = user_agent(conn)
    Logger.metadata(user_agent: user_agent)
    Logger.metadata(method: method)
    Logger.metadata(path: request_path)
    conn
  end

  defp maybe_log_http_details(%Plug.Conn{} = conn, false = _log_user_agent), do: conn

  defp maybe_block_request(%Plug.Conn{} = conn, [] = _block_keywords), do: conn

  defp maybe_block_request(%Plug.Conn{request_path: request_path} = conn, keywords) do
    user_agent = user_agent(conn)

    if user_agent == "" or String.contains?(user_agent, keywords) do
      Logger.info("Blocked request #{request_path} by user-agent: #{user_agent}")

      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(401, "Unauthorized")
      |> halt()
    else
      conn
    end
  end

  defp maybe_allow_user_agent(%Plug.Conn{halted: true} = conn, _), do: conn

  defp maybe_allow_user_agent(%Plug.Conn{} = conn, [] = _allow_user_agents) do
    PhoenixDDoS.call(conn, nil)
  end

  defp maybe_allow_user_agent(%Plug.Conn{} = conn, allow_user_agents) do
    if user_agent(conn) in allow_user_agents do
      conn
    else
      PhoenixDDoS.call(conn, nil)
    end
  end

  @doc """
  iex> user_agent(%Plug.Conn{req_headers: [{"user-agent", "foo"}]})
  "foo"
  iex> user_agent(%Plug.Conn{req_headers: [{"accept", "application/json"}]})
  "user-agent-not-set"
  """
  def user_agent(%Plug.Conn{} = conn) do
    case get_req_header(conn, "user-agent") do
      # HTTP request does not include a user agent.
      # At the moment we allow it and replace with a static value
      [] -> "user-agent-not-set"
      [user_agent] -> user_agent
    end
  end
end
