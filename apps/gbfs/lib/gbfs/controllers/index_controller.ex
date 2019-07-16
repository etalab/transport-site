defmodule GBFS.IndexController do
    use GBFS, :controller
    use Phoenix.Controller

    plug :put_view, GBFS.FeedView

    def index(%{assigns: %{networks: networks}} = conn, _params) do
        conn
        |> assign(:data, networks |> Enum.map(& %{
            gbfs: %{
                name: &1,
                _links: %{
                    "gbfs.json" => %{
                        href: current_url(conn) <> &1 <> "/gbfs.json"
                    }
                }
            }
        }))
        |> render
    end
end
