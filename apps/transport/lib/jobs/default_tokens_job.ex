defmodule Transport.Jobs.DefaultTokensJob do
  @moduledoc """
  This job is in charge of creating a default token for relevant contacts.

  A default token is created for all members of an organization
  if the organization has a single token and the contact
  doesn't have a default token already.
  """

  use Oban.Worker, max_attempts: 3

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
    query = """
    select
      c.id contact_id,
      co.organization_id
    from contact c
    join contacts_organizations co on co.contact_id = c.id
    where
      co.organization_id in (
        select t.organization_id
        from token t
        group by 1
        having count(1) = 1
      )
     and c.id not in (select contact_id from default_token)
    """

    %Postgrex.Result{columns: columns, rows: rows} = Ecto.Adapters.SQL.query!(DB.Repo, query)

    rows
    |> Enum.map(fn row ->
      args = columns |> Enum.zip(row) |> Map.new()
      __MODULE__.new(args)
    end)
    |> Oban.insert_all()

    :ok
  end
end
