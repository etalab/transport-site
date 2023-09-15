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
    url =
      conn
      |> current_url()
      |> Path.join(network)
      |> Path.join("gbfs.json")

    %{
      gbfs: %{
        name: network,
        _links: %{
          "gbfs.json" => %{href: url}
        }
      }
    }
  end

  def not_found(%Plug.Conn{} = conn, _params) do
    conn
    |> put_status(:not_found)
    |> text("Network not found. See available data: https://transport.data.gouv.fr/datasets?type=bike-scooter-sharing")
  end
end
