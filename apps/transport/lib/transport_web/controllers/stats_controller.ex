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

  @spec stats_public_transit(Plug.Conn.t(), any) :: Plug.Conn.t()
  def stats_public_transit(conn, _params) do
    dashboard_id = 18

    conn
    |> assign(:metabase_token, metabase_token(dashboard_id))
    |> render("metabase_dashboard.html")
  end

  defp metabase_token(dashboard_id) do
    secret = Application.fetch_env!(:transport, :metabase_secret_key)
    now = System.os_time(:second)

    header = Base.url_encode64(Jason.encode!(%{"alg" => "HS256", "typ" => "JWT"}), padding: false)

    payload =
      Base.url_encode64(
        Jason.encode!(%{
          "resource" => %{"dashboard" => dashboard_id},
          "params" => %{},
          "exp" => now + 600
        }),
        padding: false
      )

    message = "#{header}.#{payload}"
    signature = :crypto.mac(:hmac, :sha256, secret, message) |> Base.url_encode64(padding: false)

    "#{message}.#{signature}"
  end
end
