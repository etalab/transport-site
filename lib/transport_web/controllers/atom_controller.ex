defmodule TransportWeb.AtomController do
  use TransportWeb, :controller
  alias Transport.{Repo, Resource}
  import Ecto.Query

  def index(conn, _params) do
    resources = Resource
    |> preload(:dataset)
    |> select(
      [r],
      struct(r, [:id, :last_update, :title, :latest_url, :dataset_id,
        dataset: [:spatial, :description, :organization]]))
    |> where([r], not is_nil(r.latest_url))
    |> Repo.all()

    conn
     |> put_layout(false)
     |> put_resp_content_type("application/xml")
     |> render("index.html", resources: resources)
  end
end
