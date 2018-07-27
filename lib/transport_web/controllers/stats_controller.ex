defmodule TransportWeb.StatsController do
  use TransportWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
