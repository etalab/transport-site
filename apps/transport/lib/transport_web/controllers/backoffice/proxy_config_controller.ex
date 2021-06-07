defmodule TransportWeb.Backoffice.ProxyConfigController do
  use TransportWeb, :controller

  def index(conn, _params) do
    conn
    |> render("index.html")
  end
end
