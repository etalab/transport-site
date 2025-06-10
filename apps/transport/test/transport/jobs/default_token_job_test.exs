defmodule Transport.Test.Transport.Jobs.DefaultTokensJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.DefaultTokensJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "enqueues jobs" do
    %DB.Organization{id: organization_id} = organization = insert(:organization)
    o2 = insert(:organization)

    %DB.Contact{id: c1_id} =
      insert_contact(%{
        organizations: [organization |> Map.from_struct()]
      })

    c2 =
      insert_contact(%{
        organizations: [o2 |> Map.from_struct()]
      })

    insert_token(%{organization_id: organization.id})

    # 2 tokens for the same org, should not be enqueued
    t2 = insert_token()
    insert_token(%{organization_id: t2.organization_id, name: "other"})

    # c2 already has a default token
    t4 = insert_token(%{organization_id: o2.id})
    insert(:default_token, %{token: t4, contact: c2})

    assert :ok == perform_job(DefaultTokensJob, %{})

    assert [
             %Oban.Job{
               state: "available",
               worker: "Transport.Jobs.DefaultTokensJob",
               args: %{"contact_id" => ^c1_id, "organization_id" => ^organization_id}
             }
           ] = all_enqueued()
  end

  describe "perform" do
    test "creates a default token" do
      organization = insert(:organization)

      contact =
        insert_contact(%{
          organizations: [organization |> Map.from_struct()]
        })

      %DB.Token{id: t1_id} = insert_token(%{organization_id: organization.id})

      assert :ok == perform_job(DefaultTokensJob, %{contact_id: contact.id, organization_id: organization.id})

      assert [%DB.Token{id: ^t1_id}] = DB.Repo.preload(contact, :default_tokens).default_tokens
    end

    test "does not create a default token if the contact already has one" do
      organization = insert(:organization)

      contact =
        insert_contact(%{
          organizations: [organization |> Map.from_struct()]
        })

      %DB.Token{id: token_id} = token = insert_token(%{organization_id: organization.id})
      insert(:default_token, %{token: token, contact: contact})

      assert {:cancel, "Contact##{contact.id} already has a default token"} ==
               perform_job(DefaultTokensJob, %{contact_id: contact.id, organization_id: organization.id})

      assert [%DB.Token{id: ^token_id}] = DB.Repo.preload(contact, :default_tokens).default_tokens
    end
  end
end
