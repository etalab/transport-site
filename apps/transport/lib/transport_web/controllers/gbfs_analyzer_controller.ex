defmodule TransportWeb.GbfsAnalyzerController do
  use TransportWeb, :controller

  def index(conn, %{"url" => gbfs_url}) when gbfs_url !== "" do
    metadata = Transport.GBFSMetadata.compute_feed_metadata(gbfs_url)

    conn
    |> assign(:gbfs_url, gbfs_url)
    |> assign(:metadata, metadata)
    |> render("index.html")
  end

  def index(conn, _params) do
    conn |> redirect(to: live_path(conn, TransportWeb.Live.OnDemandValidationSelectLive, type: "gbfs"))
  end
end
