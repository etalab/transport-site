defmodule TransportWeb.ReuseController do
  @moduledoc """
  Controller for data.gouv.fr reuses.
  """
  use TransportWeb, :controller

  def index(%Plug.Conn{} = conn, params) do
    config = make_pagination_config(params)
    reuses = DB.Reuse.base_query() |> DB.Repo.paginate(page: config.page_number)

    render(conn, "index.html", reuses: reuses)
  end
end
