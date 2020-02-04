defmodule GBFS.IndexController do
  use GBFS, :controller

  plug(:put_view, GBFS.FeedView)

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%{assigns: %{networks: networks}} = conn, _params) do
    conn
    |> assign(:data, networks |> Enum.map(&create_gbfs_links(&1, conn)))
    |> render
  end

  @spec create_gbfs_links(binary(), Plug.Conn.t()) :: %{gbfs: %{name: binary(), _links: map()}}
  defp create_gbfs_links(network, conn) do
    %{
      gbfs: %{
        name: network,
        _links: %{
          "gbfs.json" => %{href: current_url(conn) <> network <> "/gbfs.json"}
        }
      }
    }
  end
end
