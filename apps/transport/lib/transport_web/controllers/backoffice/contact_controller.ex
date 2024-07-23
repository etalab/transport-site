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
    |> assign(:contact, DB.Contact.changeset(%DB.Contact{}, params))
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
  def edit(%Plug.Conn{} = conn, %{"id" => contact_id} = params) do
    conn
    |> assign(:contact, DB.Contact.changeset(existing_contact(params), %{}))
    |> assign(:contact_id, contact_id)
    |> render_form()
  end

  def delete(%Plug.Conn{} = conn, %{"id" => _} = params) do
    params |> existing_contact() |> DB.Repo.delete!()

    conn
    |> put_flash(:info, "Le contact a été supprimé")
    |> redirect(to: backoffice_contact_path(conn, :index))
  end

  defp render_form(%Plug.Conn{assigns: assigns} = conn) do
    contact_id = Map.get(assigns, :contact_id)

    conn
    |> assign(:existing_organizations, contact_values_for_field(:organization))
    |> assign(:existing_job_titles, contact_values_for_field(:job_title))
    |> assign(:datasets_datalist, datasets_datalist())
    |> assign(:notification_subscriptions, notification_subscriptions_for_contact(contact_id))
    |> assign(:notifications, notifications_for_contact(contact_id))
    |> assign(:notifications_months_limit, notifications_months_limit())
    |> render("form.html")
  end

  @spec render_index(Ecto.Queryable.t(), Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp render_index(contacts, conn, params) do
    config = make_pagination_config(params)

    paginated_result = contacts |> DB.Repo.paginate(page: config.page_number)
    paginated_contacts = paginated_result |> Map.put(:entries, paginated_result.entries)

    conn
    |> assign(:contacts, paginated_contacts)
    |> assign(:search_datalist, search_datalist())
    |> render("index.html")
  end

  def search_datalist do
    :organization
    |> contact_values_for_field()
    |> Enum.concat(contact_values_for_field(:last_name))
    |> Enum.sort()
  end

  defp contact_values_for_field(field) when is_atom(field) do
    DB.Contact.base_query()
    |> select([contact: c], field(c, ^field))
    |> where([contact: c], not is_nil(field(c, ^field)))
    |> order_by([contact: c], asc: ^field)
    |> distinct(true)
    |> DB.Repo.all()
  end

  def datasets_datalist do
    DB.Dataset.base_with_hidden_datasets()
    |> select([dataset: d], [:id, :custom_title, :type, :is_hidden])
    |> order_by([dataset: d], asc: d.custom_title)
    |> distinct(true)
    |> DB.Repo.all()
  end

  defp notification_subscriptions_for_contact(contact_id) when is_binary(contact_id) do
    DB.NotificationSubscription.base_query()
    |> preload(:dataset)
    |> where([notification_subscription: ns], ns.contact_id == ^contact_id)
    |> DB.Repo.all()
  end

  defp notification_subscriptions_for_contact(nil), do: []

  defp notifications_for_contact(contact_id) when is_binary(contact_id) do
    datetime_limit = DateTime.utc_now() |> DateTime.add(-30 * notifications_months_limit(), :day)

    DB.Notification.base_query()
    |> preload(:dataset)
    |> where([notification: n], n.contact_id == ^contact_id)
    |> where([notification: n], n.inserted_at >= ^datetime_limit)
    |> order_by([notification: n], desc: n.inserted_at)
    |> DB.Repo.all()
  end

  defp notifications_for_contact(nil), do: []

  @spec notifications_months_limit :: pos_integer()
  def notifications_months_limit, do: 6
end
