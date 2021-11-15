defmodule TransportWeb.Plugs.Halt do
  @moduledoc """
    When the app runs on worker-only (Oban) mode, we still need a HTTP endpoint so that the hosting
    provider monitoring can verify the app is up. In that case, though, we want to avoid serving the
    routes we normally serve, as early as possible ; such is the purpose of this plug.
  """
  import Plug.Conn

  def init(options), do: options

  def call(conn, opts) do
    {mod, fun} = opts[:if]

    if apply(mod, fun, []) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, opts[:message])
      |> halt()
    else
      conn
    end
  end
end
