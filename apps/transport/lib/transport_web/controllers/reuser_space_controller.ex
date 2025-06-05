defmodule TransportWeb.ReuserSpaceController do
  use TransportWeb, :controller
  import Ecto.Query

  plug(
    :find_contact
    when action in [:espace_reutilisateur, :settings, :new_token, :create_new_token, :delete_token, :default_token]
  )

  plug(:find_dataset_or_redirect when action in [:datasets_edit, :unfavorite, :add_improved_data])

  def espace_reutilisateur(%Plug.Conn{assigns: %{contact: %DB.Contact{} = contact}} = conn, _) do
    followed_datasets_ids = contact |> Ecto.assoc(:followed_datasets) |> select([d], d.id) |> DB.Repo.all()

    conn
    |> assign(:contact, contact)
    |> assign(:followed_datasets_ids, followed_datasets_ids)
    |> render("index.html")
  end

  def settings(%Plug.Conn{assigns: %{contact: %DB.Contact{} = contact}} = conn, _) do
    conn
    |> assign(:tokens, tokens(contact))
    |> render("settings.html")
  end

  def delete_token(%Plug.Conn{assigns: %{contact: %DB.Contact{} = contact}} = conn, %{"id" => token_id}) do
    contact
    |> tokens()
    |> Enum.find(&(to_string(&1.id) == token_id))
    |> DB.Repo.delete!()

    maybe_default_token(contact)

    conn
    |> put_flash(:info, dgettext("reuser-space", "Your token has been deleted"))
    |> redirect(to: reuser_space_path(conn, :settings))
  end

  def default_token(%Plug.Conn{assigns: %{contact: %DB.Contact{id: contact_id} = contact}} = conn, %{"id" => token_id}) do
    DB.DefaultToken.base_query()
    |> where([default_token: df], df.contact_id == ^contact_id)
    |> DB.Repo.delete_all()

    token = contact |> tokens() |> Enum.find(&(to_string(&1.id) == token_id))

    %DB.DefaultToken{}
    |> DB.DefaultToken.changeset(%{token_id: token.id, contact_id: contact_id})
    |> DB.Repo.insert!()

    conn
    |> put_flash(:info, dgettext("reuser-space", "The token %{name} is now the default token", name: token.name))
    |> redirect(to: reuser_space_path(conn, :settings))
  end

  def new_token(%Plug.Conn{assigns: %{contact: %DB.Contact{} = contact}} = conn, _) do
    conn
    |> assign(:organizations, contact.organizations)
    |> assign(:errors, [])
    |> render("new_token.html")
  end

  def create_new_token(%Plug.Conn{assigns: %{contact: %DB.Contact{} = contact}} = conn, params) do
    [organization] = Enum.filter(contact.organizations, &(&1.id == params["organization_id"]))

    changeset =
      DB.Token.changeset(%DB.Token{}, %{
        "contact_id" => contact.id,
        "organization_id" => organization.id,
        "name" => params["name"]
      })

    if changeset.valid? do
      changeset |> DB.Repo.insert!()
      maybe_default_token(contact)

      conn
      |> put_flash(:info, dgettext("reuser-space", "Your token has been created"))
      |> redirect(to: reuser_space_path(conn, :settings))
    else
      conn
      |> assign(:organizations, contact.organizations)
      |> assign(:errors, changeset.errors)
      |> render("new_token.html")
    end
  end

  defp maybe_default_token(%DB.Contact{} = contact) do
    default_token_id =
      case contact.default_tokens do
        [%DB.Token{id: t_id}] -> t_id
        _ -> nil
      end

    case contact |> tokens() do
      [%DB.Token{id: token_id}] when token_id != default_token_id and is_nil(default_token_id) ->
        %DB.DefaultToken{}
        |> DB.DefaultToken.changeset(%{token_id: token_id, contact_id: contact.id})
        |> DB.Repo.insert!()

      _ ->
        :ok
    end
  end

  def datasets_edit(
        %Plug.Conn{assigns: %{dataset: %DB.Dataset{} = dataset, contact: %DB.Contact{} = contact}} = conn,
        _
      ) do
    eligible_organizations = data_sharing_eligible_orgs(contact)

    conn
    |> assign(:contact, contact)
    |> assign(:dataset, DB.Repo.preload(dataset, :resources))
    |> assign(:eligible_to_data_sharing_pilot, data_sharing_pilot?(dataset, contact))
    |> assign(:eligible_organizations, eligible_organizations)
    |> assign(:existing_improved_data, existing_improved_data(dataset, eligible_organizations))
    |> render("datasets_edit.html")
  end

  defp existing_improved_data(%DB.Dataset{id: dataset_id}, [%DB.Organization{id: organization_id}]) do
    DB.ReuserImprovedData
    |> where([r], r.dataset_id == ^dataset_id and r.organization_id == ^organization_id)
    |> DB.Repo.one()
  end

  defp existing_improved_data(%DB.Dataset{}, _orgs), do: nil

  def add_improved_data(
        %Plug.Conn{
          assigns: %{dataset: %DB.Dataset{} = dataset, contact: %DB.Contact{} = contact},
          params: %{
            "resource_id" => resource_id,
            "organization_id" => organization_id,
            "download_url" => download_url
          }
        } = conn,
        _
      ) do
    DB.ReuserImprovedData.changeset(%DB.ReuserImprovedData{}, %{
      dataset_id: dataset.id,
      resource_id: resource_id,
      contact_id: contact.id,
      organization_id: organization_id,
      download_url: download_url
    })
    |> DB.Repo.insert!()

    conn
    |> put_flash(:info, dgettext("reuser-space", "Your improved data has been saved."))
    |> redirect(to: reuser_space_path(conn, :datasets_edit, dataset.id))
  end

  def unfavorite(%Plug.Conn{assigns: %{dataset: %DB.Dataset{} = dataset, contact: %DB.Contact{} = contact}} = conn, _) do
    DB.DatasetFollower.unfollow!(contact, dataset)
    delete_notification_subscriptions(contact, dataset)

    conn
    |> put_flash(
      :info,
      dgettext("reuser-space", "%{dataset_title} has been removed from your favorites",
        dataset_title: dataset.custom_title
      )
    )
    |> redirect(to: reuser_space_path(conn, :espace_reutilisateur))
  end

  defp delete_notification_subscriptions(%DB.Contact{id: contact_id}, %DB.Dataset{id: dataset_id}) do
    DB.NotificationSubscription.base_query()
    |> where([notification_subscription: ns], ns.contact_id == ^contact_id and ns.dataset_id == ^dataset_id)
    |> DB.Repo.delete_all()
  end

  defp find_dataset_or_redirect(
         %Plug.Conn{assigns: %{current_user: %{"id" => datagouv_user_id}}, path_params: %{"dataset_id" => dataset_id}} =
           conn,
         _options
       ) do
    # This query makes sure that the dataset is in the user's favorites
    DB.Contact.base_query()
    |> join(:inner, [contact: c], d in assoc(c, :followed_datasets), as: :dataset)
    |> where([contact: c], c.datagouv_user_id == ^datagouv_user_id)
    |> where([dataset: d], d.id == ^dataset_id)
    |> select([contact: c, dataset: d], %{contact: c, dataset: d})
    |> DB.Repo.all()
    |> case do
      [%{contact: %DB.Contact{} = contact, dataset: %DB.Dataset{} = dataset}] ->
        conn
        |> merge_assigns(%{
          contact: DB.Repo.preload(contact, :organizations),
          dataset: dataset
        })

      _ ->
        conn
        |> put_flash(:error, dgettext("alert", "Unable to get this dataset for the moment"))
        |> redirect(to: reuser_space_path(conn, :espace_reutilisateur))
        |> halt()
    end
  end

  defp find_contact(%Plug.Conn{assigns: %{current_user: %{"id" => datagouv_user_id}}} = conn, _options) do
    contact =
      DB.Contact
      |> DB.Repo.get_by!(datagouv_user_id: datagouv_user_id)
      |> DB.Repo.preload([:organizations, :default_tokens])

    conn |> assign(:contact, contact)
  end

  @doc """
  Is the following dataset eligible for the data sharing pilot for this contact, member
  of various organizations?
  """
  @spec data_sharing_pilot?(DB.Dataset.t(), DB.Contact.t()) :: boolean()
  def data_sharing_pilot?(%DB.Dataset{} = dataset, %DB.Contact{} = contact) do
    eligible_dataset_type = dataset.type == "public-transit"
    has_dataset_tag = DB.Dataset.has_custom_tag?(dataset, config_value(:dataset_custom_tag))
    member_eligible_org = data_sharing_eligible_orgs(contact) |> Enum.count() == 1

    Enum.all?([eligible_dataset_type, has_dataset_tag, member_eligible_org])
  end

  def data_sharing_eligible_orgs(%DB.Contact{organizations: organizations}) do
    data_sharing_eligible_orgs(organizations)
  end

  def data_sharing_eligible_orgs(organizations) when is_list(organizations) do
    Enum.filter(organizations, &(&1.id in config_value(:eligible_datagouv_organization_ids)))
  end

  defp config_value(key) do
    Application.fetch_env!(:transport, :"data_sharing_pilot_#{key}")
  end

  defp tokens(%DB.Contact{} = contact) do
    organization_ids = Enum.map(contact.organizations, & &1.id)

    DB.Token.base_query()
    |> where([token: t], t.organization_id in ^organization_ids)
    |> order_by([token: t], t.inserted_at)
    |> preload(:organization)
    |> DB.Repo.all()
  end
end
