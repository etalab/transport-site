defmodule TransportWeb.Plugs.BlockUserAgent do
  @moduledoc """
  A Plug to:
  - log the User-Agent making an HTTP request
  - block HTTP requests when certain keywords are found in the User-Agent HTTP header

  Options:
  - log_user_agent: boolean or string
  - block_user_agent_keywords: list of keywords or string that will be split on `|`

  If the plug is configured with a magic value, `:use_env_variables`, the
  `call/2` method will be configured at runtime using environment variables.
  - LOG_USER_AGENT
  - BLOCK_USER_AGENT_KEYWORDS
  """
  require Logger
  import Plug.Conn
  @behaviour Plug

  @impl true
  def init(:use_env_variables), do: :use_env_variables

  def init(log_user_agent: log_user_agent, block_user_agent_keywords: block_user_agent_keywords)
      when is_binary(log_user_agent) and is_binary(block_user_agent_keywords) do
    keywords = if block_user_agent_keywords == "", do: [], else: block_user_agent_keywords |> String.split("|")

    init(
      log_user_agent: log_user_agent == "true",
      block_user_agent_keywords: keywords
    )
  end

  def init(options) do
    Keyword.validate!(options, log_user_agent: false, block_user_agent_keywords: [])
  end

  @impl true
  def call(%Plug.Conn{} = conn, :use_env_variables) do
    options =
      init(
        log_user_agent: System.get_env("LOG_USER_AGENT", "false"),
        block_user_agent_keywords: System.get_env("BLOCK_USER_AGENT_KEYWORDS", "")
      )

    call(conn, options)
  end

  def call(%Plug.Conn{} = conn, options) do
    maybe_log_http_details(conn, Keyword.fetch!(options, :log_user_agent))
    maybe_block_request(conn, Keyword.fetch!(options, :block_user_agent_keywords))
  end

  defp maybe_log_http_details(%Plug.Conn{method: method, request_path: request_path} = conn, true = _log_user_agent) do
    [user_agent] = get_req_header(conn, "user-agent")
    Logger.metadata(http_user_agent: user_agent)
    Logger.metadata(http_method: method)
    Logger.metadata(http_path: request_path)
  end

  defp maybe_log_http_details(%Plug.Conn{}, false = _log_user_agent), do: :ok

  defp maybe_block_request(%Plug.Conn{} = conn, [] = _block_keywords), do: conn

  defp maybe_block_request(%Plug.Conn{request_path: request_path} = conn, keywords) do
    [user_agent] = get_req_header(conn, "user-agent")

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
end
