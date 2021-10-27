defmodule TransportWeb.Plugs.Webserver do
  @moduledoc """
    Simple plug to skip the routing when the application is not started in webserver mode (typically a worker).
    We keep a single HTTP get up endpoint for the server monitoring purpose
  """
  import Phoenix.Controller
  import Plug.Conn

  def init(options), do: options

  def call(conn, opts) do
    conn
  else
    if Application.get_env(:transport, :webserver) == "1" do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, "UP")
      |> halt()
    end
  end
end
