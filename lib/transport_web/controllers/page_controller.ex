defmodule TransportWeb.PageController do
  use TransportWeb, :controller
  alias Transport.Datagouvfr.Client

  def index(conn, _params) do
    render conn, "index.html"
  end

  def login(conn, _) do
    render conn, "login.html"
  end

end
