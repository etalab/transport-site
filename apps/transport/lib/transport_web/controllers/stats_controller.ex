defmodule TransportWeb.StatsController do
  use TransportWeb, :controller

  @spec index(Plug.Conn.t(), any) :: Plug.Conn.t()
  def index(conn, _params) do
    stats = Transport.StatsHandler.compute_stats()

    conn =
      stats
      |> Enum.reduce(conn, fn {k, v}, conn -> conn |> assign(k, v) end)

    conn
    |> assign(:droms, ["antilles", "guyane", "mayotte", "reunion"])
    |> render("index.html")
  end
end
