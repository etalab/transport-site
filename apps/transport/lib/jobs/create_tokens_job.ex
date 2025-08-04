defmodule Transport.Jobs.CreateTokensJob do
  @moduledoc """
  This job is in charge of creating a default token for each
  organization without a token.

  The created token is then set as the default token for all
  members of this organization.
  """
  use Oban.Worker, max_attempts: 3, tags: ["tokens"]
  import Ecto.Query

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

  # Sets a default token for members of an organization without a default token.
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "set_default_token_for_contacts"}}) do
    contact_ids_default_token =
      DB.DefaultToken.base_query()
      |> select([default_token: dt], dt.contact_id)

    contact_ids_in_org =
      DB.Contact.base_query()
      |> join(:inner, [contact: c], o in assoc(c, :organizations), as: :organizations)
      |> select([contact: c], c.id)
      |> distinct(true)

    DB.Contact.base_query()
    |> preload(organizations: [:tokens])
    |> where([contact: c], c.id not in subquery(contact_ids_default_token))
    |> where([contact: c], c.id in subquery(contact_ids_in_org))
    |> select([contact: c], [:id])
    |> DB.Repo.all()
    |> Enum.each(fn %DB.Contact{id: contact_id, organizations: organizations} ->
      token = organizations |> hd() |> Map.fetch!(:tokens) |> hd()

      %DB.DefaultToken{}
      |> DB.DefaultToken.changeset(%{token_id: token.id, contact_id: contact_id})
      |> DB.Repo.insert!()
    end)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
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
