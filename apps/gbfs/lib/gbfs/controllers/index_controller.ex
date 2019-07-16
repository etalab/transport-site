defmodule GBFS.IndexController do
    use GBFS, :controller
    use Phoenix.Controller

    plug :put_view, GBFS.FeedView

    def index(%{assigns: %{networks: networks}} = conn, _params) do
        conn
        |> assign(:data, networks |> Enum.map(& create_gbfs_links(&1, conn)))
        |> render
    end

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
