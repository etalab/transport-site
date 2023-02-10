defmodule TransportWeb.Backoffice.ContactController do
  use TransportWeb, :controller
  import Ecto.Query

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%Plug.Conn{} = conn, %{} = params) do
    conn = assign(conn, :q, Map.get(params, "q"))

    params
    |> DB.Contact.search()
    |> order_by([contact: c], asc: c.last_name)
    |> render_index(conn, params)
  end

  def new(%Plug.Conn{} = conn, params) do
    conn
    |> assign(:contact, DB.Contact.changeset(existing_contact(params), params))
    |> render_form()
  end

  def create(%Plug.Conn{} = conn, %{"contact" => params}) do
    case DB.Contact.changeset(existing_contact(params), params) do
      %Ecto.Changeset{valid?: false} ->
        conn |> redirect(to: backoffice_contact_path(conn, :new, params))

      %Ecto.Changeset{valid?: true} = changeset ->
        case changeset |> DB.Repo.insert_or_update() do
          {:ok, _} ->
            conn |> put_flash(:info, "Contact mis à jour") |> redirect(to: backoffice_contact_path(conn, :index))

          {:error, %Ecto.Changeset{errors: [email: {"has already been taken", _}]}} ->
            conn
            |> put_flash(:error, "Un contact existe déjà avec cette adresse e-mail")
            |> redirect(to: backoffice_contact_path(conn, :index))
        end
    end
  end

  defp existing_contact(%{"id" => id}) when id != "", do: DB.Repo.get!(DB.Contact, String.to_integer(id))
  defp existing_contact(%{}), do: %DB.Contact{}

  @spec edit(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def edit(%Plug.Conn{} = conn, %{"id" => _} = params) do
    conn
    |> assign(:contact, DB.Contact.changeset(existing_contact(params), %{}))
    |> render_form()
  end

  def delete(%Plug.Conn{} = conn, %{"id" => _} = params) do
    params |> existing_contact() |> DB.Repo.delete!()

    conn
    |> put_flash(:info, "Le contact a été supprimé")
    |> redirect(to: backoffice_contact_path(conn, :index))
  end

  defp render_form(%Plug.Conn{} = conn) do
    conn
    |> assign(:existing_organizations, existing_organizations())
    |> assign(:existing_job_titles, existing_job_titles())
    |> render("form.html")
  end

  @spec render_index(Ecto.Queryable.t(), Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp render_index(contacts, conn, params) do
    config = make_pagination_config(params)

    paginated_result = contacts |> DB.Repo.paginate(page: config.page_number)
    paginated_contacts = paginated_result |> Map.put(:entries, paginated_result.entries)

    conn
    |> assign(:contacts, paginated_contacts)
    |> assign(:existing_organizations, existing_organizations())
    |> render("index.html")
  end

  defp existing_organizations do
    DB.Contact.base_query()
    |> select([contact: c], c.organization)
    |> distinct(true)
    |> DB.Repo.all()
    |> Enum.sort()
  end

  defp existing_job_titles do
    DB.Contact.base_query()
    |> select([contact: c], c.job_title)
    |> distinct(true)
    |> DB.Repo.all()
    |> Enum.sort()
  end
end
