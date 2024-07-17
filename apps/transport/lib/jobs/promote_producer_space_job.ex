defmodule Transport.Jobs.PromoteProducerSpaceJob do
  @moduledoc """
  This job is executed when a contact logs in on the platform for the first time,
  for all contacts.

  If the contact is a producer, subscribe them to all producer notifications
  and send them an email to introduce the producer space.

  If the contact is a reuser, do nothing.
  """
  use Oban.Worker, unique: [period: :infinity], max_attempts: 3
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"contact_id" => contact_id}}) do
    contact =
      DB.Contact.base_query()
      |> preload(organizations: :datasets)
      |> where([contact: c], c.id == ^contact_id)
      |> DB.Repo.one!()

    datasets = Enum.flat_map(contact.organizations, & &1.datasets)

    unless Enum.empty?(datasets) do
      create_producer_subscriptions(contact, datasets)

      {:ok, _} = Transport.UserNotifier.promote_producer_space(contact) |> Transport.Mailer.deliver()
      save_notification(contact)
    end

    :ok
  end

  defp save_notification(%DB.Contact{id: contact_id, email: email}) do
    DB.Notification.insert!(%{
      contact_id: contact_id,
      email: email,
      reason: Transport.NotificationReason.reason(:promote_producer_space),
      role: :producer
    })
  end

  defp create_producer_subscriptions(%DB.Contact{id: contact_id}, datasets) do
    reasons = Transport.NotificationReason.subscribable_reasons_related_to_datasets(:producer)

    for reason <- reasons, %DB.Dataset{id: dataset_id} <- datasets do
      # Do not use `insert!/1`: we may try to insert duplicates (existing subscriptions)
      # and we leverage the changeset to ignore those.
      DB.NotificationSubscription.insert(%{
        role: :producer,
        source: :"automation:promote_producer_space",
        reason: reason,
        contact_id: contact_id,
        dataset_id: dataset_id
      })
    end
  end
end
