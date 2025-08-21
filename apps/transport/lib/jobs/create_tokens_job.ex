defmodule Transport.Jobs.CreateTokensJob do
  @moduledoc """
  This job is in charge of:
  - creating a default token for each organization without a token.
    The created token is then set as the default token for all
    members of this organization.
  - creating a default token for each contact without an organization.
    The created token is then set as the default.
  - creating a token for a contact.
  """
  use Oban.Worker, max_attempts: 3, tags: ["tokens"]
  import Ecto.Query

  def get_all_contact_ids_having_a_default_token do
    DB.DefaultToken.base_query()
    |> select([default_token: dt], dt.contact_id)
  end

  def get_all_contact_ids_in_org do
    DB.Contact.base_query()
    |> join(:inner, [contact: c], o in assoc(c, :organizations), as: :organizations)
    |> select([contact: c], c.id)
    |> distinct(true)
  end

  # Create a token for a contact.
  # - If the contact is not a member of an organization, a personal token
  # - Otherwise set the default token using the first organization
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "create_token_for_contact", "contact_id" => contact_id}}) do
    contact = DB.Repo.get!(DB.Contact, contact_id) |> DB.Repo.preload([:default_tokens, organizations: [:tokens]])

    if Enum.empty?(contact.default_tokens) do
      if contact.organizations |> Enum.empty?() do
        create_default_token_for_contact(contact)
      else
        set_default_token_for_contact(contact)
      end

      :ok
    else
      {:cancel, "already has a default token"}
    end
  end

  # - Create a default token for an organization
  # - Set this token as the default token for each member of the organization
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id}}) do
    contact = DB.Repo.get_by!(DB.Contact, email_hash: Application.fetch_env!(:transport, :contact_email))

    organization =
      DB.Organization
      |> DB.Repo.get!(organization_id)
      |> DB.Repo.preload(contacts: [:default_tokens])

    token =
      DB.Token.changeset(%DB.Token{}, %{
        "contact_id" => contact.id,
        "organization_id" => organization.id,
        "name" => "Défaut"
      })
      |> DB.Repo.insert!()

    organization.contacts
    |> Enum.filter(fn %DB.Contact{default_tokens: default_tokens} -> default_tokens == [] end)
    |> Enum.each(fn %DB.Contact{} = contact -> set_default_token_for_contact(token, contact) end)
  end

  # Sets a default token for members of an organization without a default token.
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "set_default_token_for_contacts"}}) do
    contact_ids_with_a_default_token = get_all_contact_ids_having_a_default_token()
    contact_ids_in_org = get_all_contact_ids_in_org()

    DB.Contact.base_query()
    |> preload(organizations: [:tokens])
    |> where([contact: c], c.id not in subquery(contact_ids_with_a_default_token))
    |> where([contact: c], c.id in subquery(contact_ids_in_org))
    |> select([contact: c], [:id])
    |> DB.Repo.all()
    |> Enum.each(&set_default_token_for_contact/1)
  end

  # - Create tokens for contacts without an organization
  # - Set this token as the default token
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "create_tokens_for_contacts_without_org"}}) do
    contact_ids_with_a_default_token = get_all_contact_ids_having_a_default_token()
    contact_ids_in_org = get_all_contact_ids_in_org()

    DB.Contact.base_query()
    |> where([contact: c], c.id not in subquery(contact_ids_with_a_default_token))
    |> where([contact: c], c.id not in subquery(contact_ids_in_org))
    |> select([contact: c], [:id])
    |> DB.Repo.all()
    |> Enum.each(&create_default_token_for_contact/1)
  end

  # - Finds organizations without a token
  # - Enqueue job to create a token for this organization
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "create_tokens_for_organizations"}}) do
    token_org_ids =
      DB.Token.base_query()
      |> select([token: t], t.organization_id)
      |> distinct(true)

    DB.Organization.base_query()
    |> where([organization: o], o.id not in subquery(token_org_ids))
    |> select([organization: o], %{organization_id: o.id})
    |> DB.Repo.all()
    |> Enum.map(&__MODULE__.new/1)
    |> Oban.insert_all()

    :ok
  end

  defp create_default_token_for_contact(%DB.Contact{id: contact_id} = contact) do
    token =
      %DB.Token{}
      |> DB.Token.changeset(%{
        contact_id: contact_id,
        organization_id: nil,
        name: "Défaut"
      })
      |> DB.Repo.insert!()

    set_default_token_for_contact(token, contact)
  end

  defp set_default_token_for_contact(%DB.Contact{organizations: organizations} = contact) do
    token = organizations |> hd() |> Map.fetch!(:tokens) |> hd()

    set_default_token_for_contact(token, contact)
  end

  defp set_default_token_for_contact(%DB.Token{id: token_id}, %DB.Contact{id: contact_id}) do
    %DB.DefaultToken{}
    |> DB.DefaultToken.changeset(%{token_id: token_id, contact_id: contact_id})
    |> DB.Repo.insert!()
  end
end
