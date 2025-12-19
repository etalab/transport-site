defmodule Transport.Test.Transport.Jobs.VisitProxyStatisticsJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Swoosh.TestAssertions
  alias Transport.Jobs.VisitProxyStatisticsJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    on_exit(fn -> assert_no_email_sent() end)
  end

  test "perform" do
    # Should be ignored
    insert_contact()

    %DB.Organization{id: organization_id} = insert(:organization)
    %DB.Contact{id: contact_id} = contact = insert_contact(%{organizations: [%{id: organization_id}]})
    dataset = insert(:dataset, organization_id: organization_id)
    insert(:resource, dataset: dataset, url: "https://proxy.transport.data.gouv.fr/resource/example")
    insert(:resource, dataset: dataset, url: "https://proxy.transport.data.gouv.fr/resource/other_resource")

    assert [%DB.Contact{id: ^contact_id}] = VisitProxyStatisticsJob.relevant_contacts()

    assert :ok == perform_job(VisitProxyStatisticsJob, %{})

    html_content = "vous pouvez consulter et télécharger des statistiques d’utilisation de vos données"

    assert_email_sent(
      from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
      to: [{DB.Contact.display_name(contact), contact.email}],
      subject: "Découvrez vos statistiques proxy",
      html_body: ~r/#{html_content}/
    )
  end
end
