defmodule TransportWeb.AtomController do
  use TransportWeb, :controller
  alias Transport.{Repo, Resource}
  import Ecto.Query

  def index(conn, _params) do
    resources = Resource |> preload(:dataset) |> Repo.all |> Enum.reject(fn r -> is_nil(r.last_update) end)
    conn
     |> put_layout(:none)
     |> put_resp_content_type("application/xml")
     |> render("index.xml", resources: resources)
  end
end
