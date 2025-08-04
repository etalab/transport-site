defmodule Transport.Jobs.CreateTokensJob do
  @moduledoc """
  This job is in charge of:
  - creating a default token for each organization without a token.
    The created token is then set as the default token for all
    members of this organization.
  - creating a default token for each contact without an organization.
    The created token is then set as the default.
  """
  use Oban.Worker, max_attempts: 3, tags: ["tokens"]
  import Ecto.Query

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
    |> Enum.each(fn %DB.Contact{} = contact ->
      %DB.DefaultToken{}
      |> DB.DefaultToken.changeset(%{token_id: token.id, contact_id: contact.id})
      |> DB.Repo.insert!()
    end)
  end

  # - Create tokens for contacts without an organization
  # - Set this token as the default token
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "create_tokens_for_contacts_without_org"}}) do
    contact_ids_default_token =
      DB.DefaultToken.base_query()
      |> select([default_token: dt], dt.contact_id)

    contact_ids_in_org =
      DB.Contact.base_query()
      |> join(:inner, [contact: c], o in assoc(c, :organizations), as: :organizations)
      |> select([contact: c], c.id)
      |> distinct(true)

    DB.Contact.base_query()
    |> where([contact: c], c.id not in subquery(contact_ids_default_token))
    |> where([contact: c], c.id not in subquery(contact_ids_in_org))
    |> select([contact: c], %{contact_id: c.id})
    |> DB.Repo.all()
    |> Enum.each(fn %{contact_id: contact_id} ->
      token =
        %DB.Token{}
        |> DB.Token.changeset(%{
          contact_id: contact_id,
          organization_id: nil,
          name: "Défaut"
        })
        |> DB.Repo.insert!()

      %DB.DefaultToken{}
      |> DB.DefaultToken.changeset(%{token_id: token.id, contact_id: contact_id})
      |> DB.Repo.insert!()
    end)
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
end
