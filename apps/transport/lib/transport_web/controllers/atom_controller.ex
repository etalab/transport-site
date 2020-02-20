defmodule TransportWeb.AtomController do
  use TransportWeb, :controller
  alias DB.{Repo, Resource}
  import Ecto.Query

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    resources =
      Resource
      |> preload(:dataset)
      |> where([r], not is_nil(r.latest_url))
      |> Repo.all()

    conn
    |> put_layout(false)
    |> put_resp_content_type("application/xml")
    |> render("index.html", resources: resources)
  end
end
