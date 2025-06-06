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
