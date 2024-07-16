defmodule Transport.Jobs.NotificationSubscriptionProducerJob do
  @moduledoc """
  Job in charge identifying `NotificationSubscription` objects for
  which the contact subscribed as a reuser and is now a producer
  of the associated dataset.

  The job deletes these notification subscriptions and creates
  notification subscriptions for all producer reasons.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    records =
      DB.NotificationSubscription.base_query()
      |> join(:inner, [notification_subscription: ns], c in assoc(ns, :contact), as: :contact)
      |> join(:inner, [contact: c], c in assoc(c, :organizations), as: :organization)
      |> join(:inner, [notification_subscription: ns, contact: c, organization: o], d in assoc(ns, :dataset),
        on: d.organization_id == o.id,
        as: :dataset
      )
      |> where([notification_subscription: ns], ns.role == :reuser)
      |> select([notification_subscription: ns], ns)
      |> DB.Repo.all()

    # Delete reusers subscriptions
    records |> Enum.each(&DB.Repo.delete!/1)

    create_producer_subscriptions(records)

    :ok
  end

  defp create_producer_subscriptions(subscriptions) do
    subscriptions
    |> Enum.map(fn %DB.NotificationSubscription{} = ns ->
      ns |> Map.from_struct() |> Map.take([:contact_id, :dataset_id])
    end)
    |> Enum.uniq()
    |> Enum.each(&create_subscriptions/1)
  end

  defp create_subscriptions(%{contact_id: _, dataset_id: _} = attrs) do
    Transport.NotificationReason.subscribable_reasons_related_to_datasets(:producer)
    |> Enum.each(fn reason ->
      DB.NotificationSubscription.insert!(
        Map.merge(%{role: :producer, source: :"automation:migrate_from_reuser_to_producer", reason: reason}, attrs)
      )
    end)
  end
end
