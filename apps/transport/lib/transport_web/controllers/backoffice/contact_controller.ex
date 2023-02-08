defmodule TransportWeb.Backoffice.ContactController do
  use TransportWeb, :controller

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%Plug.Conn{} = conn, %{} = params) do
    conn = assign(conn, :q, Map.get(params, "q"))

    params
    |> DB.Contact.search()
    |> render_index(conn, params)
  end

  @spec edit(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def edit(%Plug.Conn{} = conn, %{"contact_id" => contact_id}) do
    text(conn, contact_id)
  end

  @spec render_index(Ecto.Queryable.t(), Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp render_index(contacts, conn, params) do
    config = make_pagination_config(params)

    paginated_result = contacts |> DB.Repo.paginate(page: config.page_number)
    paginated_contacts = paginated_result |> Map.put(:entries, paginated_result.entries)

    conn
    |> assign(:contacts, paginated_contacts)
    |> render("index.html")
  end
end
