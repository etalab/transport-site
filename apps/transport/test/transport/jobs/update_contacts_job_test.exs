defmodule Transport.Test.Transport.Jobs.UpdateContactsJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.UpdateContactsJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "enqueues jobs" do
    insert_contact()
    insert_contact(%{datagouv_user_id: user_id_1 = Ecto.UUID.generate()})
    insert_contact(%{datagouv_user_id: user_id_2 = Ecto.UUID.generate()})
    assert :ok == perform_job(UpdateContactsJob, %{})

    assert [
             %Oban.Job{
               worker: "Transport.Jobs.UpdateContactsJob",
               state: "scheduled",
               args: %{"contact_ids" => contact_ids}
             }
           ] = all_enqueued()

    assert MapSet.new(contact_ids) == MapSet.new([user_id_1, user_id_2])
  end

  test "updates organizations" do
    contact = insert_contact(%{datagouv_user_id: user_id = Ecto.UUID.generate(), organization: nil})
    url = "https://demo.data.gouv.fr/api/1/users/#{user_id}/"

    org = %{
      "acronym" => nil,
      "badges" => [],
      "id" => org_id = Ecto.UUID.generate(),
      "logo" => "https://static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-original.png",
      "logo_thumbnail" => "https://static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-100.png",
      "name" => org_name = "PAN",
      "slug" => "equipe-transport-data-gouv-fr"
    }

    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, ^url, "", [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"organizations" => [org]})}}
    end)

    assert :ok == perform_job(UpdateContactsJob, %{contact_ids: [user_id]})

    contact = contact |> DB.Repo.reload!() |> DB.Repo.preload([:organizations])
    assert [%DB.Organization{name: ^org_name, id: ^org_id}] = contact.organizations
    assert %DB.Contact{organization: ^org_name} = contact
  end
end
