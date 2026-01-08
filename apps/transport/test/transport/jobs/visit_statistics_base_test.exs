defmodule Transport.Test.Transport.Jobs.VisitStatisticsBaseTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Ecto.Query
  alias Transport.Jobs.VisitStatisticsBase

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "relevant_contacts/1" do
    test "returns unique contacts for resources matching the filter" do
      %DB.Organization{id: org_id} = insert(:organization)
      %DB.Contact{id: contact_id} = insert_contact(%{organizations: [%{id: org_id}]})

      dataset = insert(:dataset, organization_id: org_id)
      insert(:resource, dataset: dataset, url: "https://static.data.gouv.fr/example")
      insert(:resource, dataset: dataset, url: "https://other.example.com/file")

      filter_fn = &DB.Resource.hosted_on_datagouv?/1
      contacts = VisitStatisticsBase.relevant_contacts(filter_fn)

      assert [%DB.Contact{id: ^contact_id}] = contacts
    end

    test "returns empty list when no resources match filter" do
      %DB.Organization{id: org_id} = insert(:organization)
      insert_contact(%{organizations: [%{id: org_id}]})

      dataset = insert(:dataset, organization_id: org_id)
      insert(:resource, dataset: dataset, url: "https://other.example.com/file")

      filter_fn = &DB.Resource.hosted_on_datagouv?/1
      contacts = VisitStatisticsBase.relevant_contacts(filter_fn)

      assert contacts == []
    end

    test "deduplicates contacts from multiple resources" do
      %DB.Organization{id: org_id} = insert(:organization)
      %DB.Contact{id: contact_id} = insert_contact(%{organizations: [%{id: org_id}]})

      dataset = insert(:dataset, organization_id: org_id)
      insert(:resource, dataset: dataset, url: "https://static.data.gouv.fr/example1")
      insert(:resource, dataset: dataset, url: "https://static.data.gouv.fr/example2")

      filter_fn = &DB.Resource.hosted_on_datagouv?/1
      contacts = VisitStatisticsBase.relevant_contacts(filter_fn)

      # Should only return one contact despite two resources
      assert [%DB.Contact{id: ^contact_id}] = contacts
    end
  end

  describe "email_addresses_already_sent/2" do
    test "returns emails sent in the last 30 days" do
      reason = :visit_download_statistics
      %DB.Contact{email: email} = contact = insert_contact()

      insert_notification(%{
        contact_id: contact.id,
        reason: reason,
        email: email,
        role: :producer
      })

      scheduled_at = DateTime.utc_now()
      emails = VisitStatisticsBase.email_addresses_already_sent(scheduled_at, reason)

      assert email in emails
    end

    test "does not return emails sent more than 30 days ago" do
      reason = :visit_download_statistics
      %DB.Contact{email: email} = contact = insert_contact()

      # Insert old notification
      notification =
        insert_notification(%{
          contact_id: contact.id,
          reason: reason,
          email: email,
          role: :producer
        })

      # Update to make it 31 days old
      DB.Notification
      |> where([n], n.id == ^notification.id)
      |> DB.Repo.update_all(set: [inserted_at: DateTime.add(DateTime.utc_now(), -31, :day)])

      scheduled_at = DateTime.utc_now()
      emails = VisitStatisticsBase.email_addresses_already_sent(scheduled_at, reason)

      assert email not in emails
    end

    test "filters by notification reason" do
      %DB.Contact{email: email} = contact = insert_contact()

      insert_notification(%{
        contact_id: contact.id,
        reason: :visit_proxy_statistics,
        email: email,
        role: :producer
      })

      scheduled_at = DateTime.utc_now()
      emails = VisitStatisticsBase.email_addresses_already_sent(scheduled_at, :visit_download_statistics)

      assert email not in emails
    end
  end

  describe "save_notification/2" do
    test "saves notification and returns contact" do
      reason = :visit_download_statistics
      %DB.Contact{id: contact_id, email: email} = contact = insert_contact()

      result = VisitStatisticsBase.save_notification(contact, reason)

      assert %DB.Contact{id: ^contact_id} = result

      notification = DB.Repo.get_by(DB.Notification, contact_id: contact_id, reason: reason)
      assert notification.email == email
      assert notification.role == :producer
    end
  end
end
