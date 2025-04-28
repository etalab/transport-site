defmodule TransportWeb.ReuseController do
  @moduledoc """
  Controller for data.gouv.fr reuses.
  """
  use TransportWeb, :controller

  def index(%Plug.Conn{} = conn, params) do
    config = make_pagination_config(params)
    reuses = DB.Reuse.search(params) |> DB.Repo.paginate(page: config.page_number)

    conn
    |> assign(:q, params["q"])
    |> assign(:reuses, reuses)
    |> render("index.html")
  end
end
