defmodule Transport.Jobs.DefaultTokensJob do
  @moduledoc """
  This job is in charge of creating a default token for relevant contacts.

  A default token is created for all members of an organization
  if the organization has a single token and the contact
  doesn't have a default token already.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"contact_id" => contact_id, "organization_id" => organization_id}}) do
    contact = DB.Repo.get!(DB.Contact, contact_id) |> DB.Repo.preload(:default_tokens)

    if contact.default_tokens |> Enum.count() == 1 do
      {:cancel, "Contact##{contact_id} already has a default token"}
    else
      token = DB.Repo.get_by!(DB.Token, organization_id: organization_id)

      %DB.DefaultToken{}
      |> DB.DefaultToken.changeset(%{token_id: token.id, contact_id: contact.id})
      |> DB.Repo.insert!()

      :ok
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    orgs_with_single_token =
      DB.Token.base_query()
      |> select([token: t], t.organization_id)
      |> group_by([token: t], t.organization_id)
      |> having([token: t], count(t.name) == 1)

    contacts_default_token =
      DB.DefaultToken.base_query()
      |> select([default_token: dt], dt.contact_id)

    DB.Contact.base_query()
    |> join(:inner, [contact: c], o in assoc(c, :organizations), as: :organizations)
    |> where([organizations: o], o.id in subquery(orgs_with_single_token))
    |> where([contact: c], c.id not in subquery(contacts_default_token))
    |> select([contact: c, organizations: o], %{
      contact_id: c.id,
      organization_id: o.id
    })
    |> DB.Repo.all()
    |> Enum.map(&__MODULE__.new/1)
    |> Oban.insert_all()

    :ok
  end
end
