defmodule Transport.Test.Transport.Jobs.CreateTokensJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.CreateTokensJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "enqueues jobs" do
    o1 = insert(:organization)
    %DB.Organization{id: o2_id} = o2 = insert(:organization)
    insert_token(%{organization_id: o1.id})

    refute DB.Repo.preload(o1, :tokens).tokens |> Enum.empty?()
    assert DB.Repo.preload(o2, :tokens).tokens |> Enum.empty?()

    assert :ok == perform_job(CreateTokensJob, %{action: "create_tokens_for_organizations"})

    assert [
             %Oban.Job{
               state: "available",
               worker: "Transport.Jobs.CreateTokensJob",
               args: %{"organization_id" => ^o2_id}
             }
           ] = all_enqueued()
  end

  test "creates a default token for an organization" do
    %DB.Contact{id: pan_contact_id} = insert_contact(%{email: "contact@transport.data.gouv.fr"})
    %DB.Organization{id: organization_id} = organization = insert(:organization)
    c1 = insert_contact(%{organizations: [organization |> Map.from_struct()]})
    c2 = insert_contact(%{organizations: [organization |> Map.from_struct()]})

    # `c3` already has a default token, we should not try to create
    # a new one even if they are a member of `organization`.
    o2 = insert(:organization)

    c3 =
      insert_contact(%{
        organizations: [
          organization |> Map.from_struct(),
          o2 |> Map.from_struct()
        ]
      })

    token = insert_token(%{organization_id: o2.id, contact_id: c3.id})
    insert(:default_token, %{token: token, contact: c3})

    assert DB.Repo.preload(organization, :tokens).tokens |> Enum.empty?()

    assert :ok == perform_job(CreateTokensJob, %{organization_id: organization.id})

    assert [%DB.Token{id: token_id, organization_id: ^organization_id, contact_id: ^pan_contact_id, name: "Défaut"}] =
             DB.Repo.preload(organization, :tokens).tokens

    assert [%DB.Token{id: ^token_id}] = DB.Repo.preload(c1, :default_tokens).default_tokens
    assert [%DB.Token{id: ^token_id}] = DB.Repo.preload(c2, :default_tokens).default_tokens
  end

  test "set default token for contacts" do
    %DB.Organization{id: organization_id} = organization = insert(:organization)
    c1 = insert_contact(%{organizations: [organization |> Map.from_struct()]})

    # `c2` already has a default token, we should not try to create
    # a new one.
    c2 = insert_contact(%{organizations: [organization |> Map.from_struct()]})
    token = insert_token(%{organization_id: organization.id, contact_id: c2.id})
    insert(:default_token, %{token: token, contact: c2})

    # c3 is a contact without an organization and should not interfere
    _c3 = insert_contact()

    assert :ok == perform_job(CreateTokensJob, %{action: "set_default_token_for_contacts"})

    assert [%DB.Token{id: token_id, organization_id: ^organization_id}] =
             DB.Repo.preload(organization, :tokens).tokens

    assert [%DB.Token{id: ^token_id}] = DB.Repo.preload(c1, :default_tokens).default_tokens
    assert [%DB.Token{id: ^token_id}] = DB.Repo.preload(c2, :default_tokens).default_tokens
  end

  test "creates a token for contacts without an organization" do
    c1 = insert_contact(%{organizations: []})

    # c2 is a member of an organization, we should not create a token
    %DB.Organization{} = organization = insert(:organization)
    _c2 = insert_contact(%{organizations: [organization |> Map.from_struct()]})

    # c3 already has a default token, we should not try to create a new one.
    c3 = insert_contact(%{organizations: []})
    token = insert_token(%{organization_id: nil, contact_id: c3.id})
    insert(:default_token, %{token: token, contact: c3})

    assert :ok == perform_job(CreateTokensJob, %{action: "create_tokens_for_contacts_without_org"})

    assert [%DB.Token{id: token_id}] = DB.Repo.preload(c1, :tokens).tokens
    assert [%DB.Token{id: ^token_id}] = DB.Repo.preload(c1, :default_tokens).default_tokens

    # Executing the job again runs without errors
    assert :ok == perform_job(CreateTokensJob, %{action: "create_tokens_for_contacts_without_org"})
  end

  describe "create_token_for_contact" do
    test "no organizations" do
      contact = insert_contact(%{organizations: []})

      assert :ok == perform_job(CreateTokensJob, %{action: "create_token_for_contact", contact_id: contact.id})

      # Personal token has been created and is set as the default token
      assert [%DB.Token{id: token_id, name: "Défaut"}] = DB.Repo.preload(contact, :tokens).tokens
      assert [%DB.Token{id: ^token_id}] = DB.Repo.preload(contact, :default_tokens).default_tokens
    end

    test "member of an organization" do
      organization = insert(:organization)
      c1 = insert_contact(%{organizations: [organization |> Map.from_struct()]})

      c2 = insert_contact(%{organizations: [organization |> Map.from_struct()]})
      %DB.Token{id: token_id} = insert_token(%{organization_id: organization.id, contact_id: c2.id})

      assert :ok == perform_job(CreateTokensJob, %{action: "create_token_for_contact", contact_id: c1.id})

      # The default token is the one associated to the organization
      assert [%DB.Token{id: ^token_id}] = DB.Repo.preload(c1, :default_tokens).default_tokens
    end

    test "already has a default token" do
      contact = insert_contact(%{organizations: []})
      token = insert_token(%{organization_id: nil, contact_id: contact.id})
      insert(:default_token, %{token: token, contact: contact})

      assert {:cancel, "already has a default token"} ==
               perform_job(CreateTokensJob, %{action: "create_token_for_contact", contact_id: contact.id})
    end
  end
end
