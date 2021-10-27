defmodule TransportWeb.Plugs.Worker do
  @moduledoc """
    Simple plug to skip the routing when the application is started in worker mode.
    We keep a single HTTP get up endpoint for the server monitoring purpose
  """
  import Phoenix.Controller
  import Plug.Conn

  def init(options), do: options

  def call(conn, opts) do
    if Application.get_env(:transport, :worker) == "1" do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, "UP")
      |> halt()
    else
      conn
    end
  end
end
