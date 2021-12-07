defmodule TransportWeb.GbfsAnalyzerController do
  use TransportWeb, :controller

  def index(conn, %{"url" => gbfs_url}) when gbfs_url !== "" do
    metadata = Transport.GBFSMetadata.Wrapper.compute_feed_metadata(gbfs_url)

    conn
    |> assign(:gbfs_url, gbfs_url)
    |> assign(:metadata, metadata)
    |> render("index.html")
  end

  def index(conn, _params) do
    conn |> assign(:gbfs_url, "") |> render("index.html")
  end
end
