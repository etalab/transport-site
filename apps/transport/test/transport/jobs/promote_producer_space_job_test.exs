defmodule Transport.Test.Transport.Jobs.PromoteProducerSpaceJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Ecto.Query
  import Swoosh.TestAssertions
  alias Transport.Jobs.PromoteProducerSpaceJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    on_exit(fn -> assert_no_email_sent() end)
  end

  describe "perform" do
    test "does nothing if you're a reuser" do
      contact = insert_contact()
      insert(:dataset)

      assert :ok == perform_job(PromoteProducerSpaceJob, %{contact_id: contact.id})

      assert DB.NotificationSubscription |> DB.Repo.all() |> Enum.empty?()
      refute_email_sent()
    end

    test "for a producer" do
      organization = insert(:organization)

      %DB.Contact{id: contact_id, email: contact_email} =
        contact =
        insert_contact(%{organizations: [organization |> Map.from_struct()]})

      dataset = insert(:dataset, organization_id: organization.id)
      # Another dataset, should be ignored: contact is not a producer for it
      insert(:dataset)

      # An existing notification subscription in the DB before executing the job
      insert(:notification_subscription,
        dataset_id: dataset.id,
        reason: :expiration,
        role: :producer,
        contact_id: contact_id,
        source: :admin
      )

      assert :ok == perform_job(PromoteProducerSpaceJob, %{contact_id: contact_id})

      # The contact has been subscribed to all producer reasons for the dataset.
      # The existing subscription did not interfere.
      producer_reasons = Transport.NotificationReason.subscribable_reasons_related_to_datasets(:producer)

      subscriptions =
        DB.NotificationSubscription.base_query()
        |> select([notification_subscription: ns], %{
          dataset_id: ns.dataset_id,
          role: ns.role,
          contact_id: ns.contact_id,
          reason: ns.reason
        })
        |> DB.Repo.all()

      assert %{admin: 1, "automation:promote_producer_space": Enum.count(producer_reasons) - 1} ==
               DB.NotificationSubscription.base_query()
               |> select([notification_subscription: ns], ns.source)
               |> DB.Repo.all()
               |> Enum.frequencies()

      expected_subscriptions =
        MapSet.new(producer_reasons, fn reason ->
          %{dataset_id: dataset.id, role: :producer, contact_id: contact_id, reason: reason}
        end)

      assert Enum.count(subscriptions) == subscriptions |> MapSet.new() |> Enum.count()
      assert expected_subscriptions == MapSet.new(subscriptions)

      display_name = DB.Contact.display_name(contact)

      assert_email_sent(fn %Swoosh.Email{
                             from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                             to: [{^display_name, ^contact_email}],
                             reply_to: {"", "contact@transport.data.gouv.fr"},
                             subject: "Bienvenue ! Découvrez votre Espace producteur",
                             text_body: nil,
                             html_body: html_body
                           } ->
        assert html_body =~ "Bienvenue sur le Point d’Accès National aux données de transport"

        assert html_body =~
                 ~s(Rendez-vous sur votre <a href="http://127.0.0.1:5100/espace_producteur?utm_source=transactional_email&amp;utm_medium=email&amp;utm_campaign=promote_producer_space">Espace Producteur</a> pour mettre à jour vos données ou paramétrer vos notifications)
      end)

      assert [
               %DB.Notification{
                 reason: :promote_producer_space,
                 contact_id: ^contact_id,
                 email: ^contact_email,
                 role: :producer,
                 dataset_id: nil,
                 notification_subscription_id: nil
               }
             ] = DB.Notification |> DB.Repo.all()
    end
  end
end
