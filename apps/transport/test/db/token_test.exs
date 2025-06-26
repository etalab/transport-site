defmodule DB.TokenTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Ecto.Query

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "can save objects in the database with relevant casts" do
    contact = insert_contact()
    organization = insert(:organization)

    DB.Token.changeset(%DB.Token{}, %{
      contact_id: contact.id,
      organization_id: organization.id,
      name: name = "Default"
    })
    |> DB.Repo.insert!()

    assert %DB.Token{secret: secret, name: ^name} = DB.Repo.one!(DB.Token)

    # Can search using secret_hash`
    assert 1 == DB.Token |> where([n], n.secret_hash == ^secret) |> DB.Repo.all() |> Enum.count()

    # Cannot get rows by using the secret
    assert DB.Token |> where([n], n.secret == ^secret) |> DB.Repo.all() |> Enum.empty?()
  end
end
