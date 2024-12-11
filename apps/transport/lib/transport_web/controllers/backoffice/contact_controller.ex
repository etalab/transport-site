defmodule TransportWeb.Backoffice.ContactController do
  use TransportWeb, :controller
  require Logger
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
  defp existing_contact(%{}), do: %DB.Contact{creation_source: :admin}

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

  def csv_export(%Plug.Conn{assigns: %{current_user: current_user}} = conn, _params) do
    Logger.info(
      ~s|#{current_user["first_name"]} #{current_user["last_name"]} (#{current_user["id"]}) vient de télécharger un export des contacts|
    )

    filename = "contacts-#{Date.utc_today() |> Date.to_iso8601()}.csv"

    query = """
    select *
    from contact
    join (
      select
        c.id contact_id,
        count(d.id) > 0 is_producer,
        count(df.id) > 0 is_reuser,
        array_remove(array_agg(distinct o.name), null) organization_names,
        array_remove(array_agg(distinct ns_producer.reason), null) producer_reasons,
        array_remove(array_agg(distinct ns_reuser.reason), null) reuser_reasons
      from contact c
      left join contacts_organizations co on co.contact_id = c.id
      left join organization o on o.id = co.organization_id
      left join dataset d on d.organization_id = co.organization_id
      left join dataset_followers df on df.contact_id = c.id
      left join notification_subscription ns_producer on ns_producer.contact_id = c.id and ns_producer.role = 'producer'
      left join notification_subscription ns_reuser on ns_reuser.contact_id = c.id and ns_reuser.role = 'reuser'
      group by 1
    ) t on t.contact_id = id
    order by id
    """

    csv_header =
      [
        "id",
        "first_name",
        "last_name",
        "mailing_list_title",
        "email",
        "phone_number",
        "job_title",
        "organization",
        "inserted_at",
        "updated_at",
        "datagouv_user_id",
        "last_login_at",
        "creation_source",
        "organization_names",
        columns_for_role(:producer),
        columns_for_role(:reuser)
      ]
      |> List.flatten()

    {:ok, conn} =
      DB.Repo.transaction(
        fn ->
          Ecto.Adapters.SQL.stream(DB.Repo, query)
          |> Stream.map(&build_csv_rows(&1, csv_header))
          |> send_csv_response(filename, csv_header, conn)
        end,
        timeout: :timer.seconds(30)
      )

    conn
  end

  defp columns_for_role(role) do
    more_columns =
      Transport.NotificationReason.subscribable_reasons_for_role(role)
      |> Enum.map(&"#{role}_#{&1}")
      |> Enum.sort()

    ["is_#{role}" | more_columns]
  end

  defp send_csv_response(chunks, filename, csv_header, %Plug.Conn{} = conn) do
    {:ok, conn} =
      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s|attachment; filename="#{filename}"|)
      |> send_chunked(:ok)
      |> send_csv_chunk([csv_header])

    Enum.reduce_while(chunks, conn, fn data, conn ->
      case send_csv_chunk(conn, data) do
        {:ok, conn} -> {:cont, conn}
        {:error, :closed} -> {:halt, conn}
      end
    end)
  end

  defp send_csv_chunk(%Plug.Conn{} = conn, data) do
    chunk(conn, data |> NimbleCSV.RFC4180.dump_to_iodata())
  end

  defp build_csv_rows(%Postgrex.Result{rows: rows, columns: columns}, csv_header) do
    Enum.map(rows, fn row ->
      build_csv_row(csv_header, Enum.zip(columns, row) |> Enum.into(%{}))
    end)
  end

  defp build_csv_row(csv_header, row) do
    row = row |> decrypt_columns() |> add_roles_columns()

    # Build a row following same order as the CSV header
    Enum.map(csv_header, &Map.fetch!(row, &1))
  end

  defp decrypt_columns(contact_row) do
    contact_row
    |> Map.update!("email", &decrypt!/1)
    |> Map.update!("phone_number", &decrypt!/1)
  end

  defp decrypt!(nil), do: nil
  defp decrypt!(value), do: Transport.Vault.decrypt!(value)

  defp add_roles_columns(%{"producer_reasons" => _, "reuser_reasons" => _} = row) do
    row |> add_producer_columns() |> add_reuser_columns()
  end

  defp add_producer_columns(%{"producer_reasons" => producer_reasons} = row) do
    Enum.reduce(Transport.NotificationReason.subscribable_reasons_for_role(:producer), row, fn reason, row ->
      Map.put(row, "producer_#{reason}", to_string(reason) in producer_reasons)
    end)
  end

  defp add_reuser_columns(%{"reuser_reasons" => reuser_reasons} = row) do
    Enum.reduce(Transport.NotificationReason.subscribable_reasons_for_role(:reuser), row, fn reason, row ->
      Map.put(row, "reuser_#{reason}", to_string(reason) in reuser_reasons)
    end)
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
