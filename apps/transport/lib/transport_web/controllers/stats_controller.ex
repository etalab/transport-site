defmodule TransportWeb.StatsController do
  use TransportWeb, :controller

  @spec index(Plug.Conn.t(), any) :: Plug.Conn.t()
  def index(conn, _params) do
    stats =
      Transport.Cache.fetch(
        "stats-page-index",
        fn -> Transport.StatsHandler.compute_stats() end,
        Transport.PreemptiveStatsCache.cache_ttl()
      )

    conn =
      stats
      |> Enum.reduce(conn, fn {k, v}, conn -> conn |> assign(k, v) end)

    conn
    |> assign(:droms, ["antilles", "guyane", "nouvelle_caledonie", "reunion"])
    |> render("index.html")
  end
end
