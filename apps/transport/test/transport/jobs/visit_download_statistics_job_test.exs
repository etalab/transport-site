defmodule Transport.Test.Transport.Jobs.VisitDownloadStatisticsJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Swoosh.TestAssertions
  alias Transport.Jobs.VisitDownloadStatisticsJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    on_exit(fn -> assert_no_email_sent() end)
  end

  test "perform" do
    # Should be ignored
    insert_contact()

    %DB.Organization{id: organization_id} = insert(:organization)
    %DB.Contact{id: contact_id} = contact = insert_contact(%{organizations: [%{id: organization_id}]})

    # Another contact but they received the email already
    %DB.Contact{id: other_contact_id} = other_contact = insert_contact(%{organizations: [%{id: organization_id}]})

    insert_notification(%{
      contact_id: other_contact.id,
      reason: :visit_download_statistics,
      email: other_contact.email,
      role: :producer
    })

    dataset = insert(:dataset, organization_id: organization_id)
    insert(:resource, dataset: dataset, url: "https://static.data.gouv.fr/example")
    insert(:resource, dataset: dataset, url: "https://static.data.gouv.fr/other_resource")

    assert [%DB.Contact{id: ^contact_id}, %DB.Contact{id: ^other_contact_id}] =
             VisitDownloadStatisticsJob.relevant_contacts() |> Enum.sort_by(& &1.id)

    assert :ok == perform_job(VisitDownloadStatisticsJob, %{})

    html_content = "vous pouvez consulter et télécharger des statistiques de téléchargement de vos données"

    assert_email_sent(
      from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
      to: [{DB.Contact.display_name(contact), contact.email}],
      subject: "Découvrez vos statistiques de téléchargement",
      html_body: ~r/#{html_content}/
    )

    [
      %DB.Notification{
        reason: :visit_download_statistics,
        contact_id: ^other_contact_id,
        role: :producer
      },
      %DB.Notification{
        reason: :visit_download_statistics,
        contact_id: ^contact_id,
        role: :producer
      }
    ] = DB.Repo.all(DB.Notification) |> Enum.sort_by(& &1.id)
  end
end
