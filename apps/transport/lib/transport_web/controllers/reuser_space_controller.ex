defmodule TransportWeb.ReuserSpaceController do
  use TransportWeb, :controller
  import Ecto.Query

  plug(:find_contact when action in [:espace_reutilisateur, :settings, :new_token, :create_new_token])
  plug(:find_dataset_or_redirect when action in [:datasets_edit, :unfavorite, :add_improved_data])

  def espace_reutilisateur(%Plug.Conn{assigns: %{contact: %DB.Contact{} = contact}} = conn, _) do
    followed_datasets_ids = contact |> Ecto.assoc(:followed_datasets) |> select([d], d.id) |> DB.Repo.all()

    conn
    |> assign(:contact, contact)
    |> assign(:followed_datasets_ids, followed_datasets_ids)
    |> render("index.html")
  end

  def settings(%Plug.Conn{assigns: %{contact: %DB.Contact{} = contact}} = conn, _) do
    contact = DB.Repo.preload(contact, :organizations)
    organization_ids = Enum.map(contact.organizations, & &1.id)

    tokens =
      DB.Token.base_query()
      |> where([token: t], t.organization_id in ^organization_ids)
      |> preload(:organization)
      |> DB.Repo.all()

    conn
    |> assign(:tokens, tokens)
    |> render("settings.html")
  end

  def new_token(%Plug.Conn{assigns: %{contact: %DB.Contact{} = contact}} = conn, _) do
    contact = DB.Repo.preload(contact, :organizations)

    conn
    |> assign(:organizations, contact.organizations)
    |> render("new_token.html")
  end

  def create_new_token(%Plug.Conn{assigns: %{contact: %DB.Contact{} = contact}} = conn, params) do
    contact = DB.Repo.preload(contact, :organizations)
    [organization] = Enum.filter(contact.organizations, &(&1.id == params["organization_id"]))

    DB.Token.changeset(%DB.Token{}, %{
      "contact_id" => contact.id,
      "organization_id" => organization.id,
      "name" => params["name"]
    })
    |> DB.Repo.insert!()

    conn
    |> put_flash(:info, dgettext("reuser-space", "Your token has been created"))
    |> redirect(to: reuser_space_path(conn, :settings))
  end

  def datasets_edit(
        %Plug.Conn{assigns: %{dataset: %DB.Dataset{} = dataset, contact: %DB.Contact{} = contact}} = conn,
        _
      ) do
    contact = DB.Repo.preload(contact, :organizations)
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
      [%{contact: %DB.Contact{}, dataset: %DB.Dataset{}} = results] ->
        conn |> merge_assigns(results)

      _ ->
        conn
        |> put_flash(:error, dgettext("alert", "Unable to get this dataset for the moment"))
        |> redirect(to: reuser_space_path(conn, :espace_reutilisateur))
        |> halt()
    end
  end

  defp find_contact(%Plug.Conn{assigns: %{current_user: %{"id" => datagouv_user_id}}} = conn, _options) do
    conn |> assign(:contact, DB.Repo.get_by!(DB.Contact, datagouv_user_id: datagouv_user_id))
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
end
