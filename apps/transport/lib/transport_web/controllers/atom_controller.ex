defmodule TransportWeb.AtomController do
  use TransportWeb, :controller
  alias DB.{Repo, Resource}
  import Ecto.Query

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    two_weeks_ago = DateTime.utc_now() |> DateTime.add(-15, :day)

    resources = get_recently_updated_resources(two_weeks_ago)

    conn
    |> put_layout(false)
    |> put_resp_content_type("application/xml")
    |> render("index.html", resources: resources)
  end

  @spec get_recently_updated_resources(DateTime.t()) :: list
  def get_recently_updated_resources(limit_date) do
    Resource
    |> preload(:dataset)
    |> where([r], not is_nil(r.latest_url) and r.last_update >= ^limit_date)
    |> Repo.all()
    |> Enum.sort(fn r1, r2 -> DateTime.compare(r1.last_update, r2.last_update) == :gt end)
  end
end
