defmodule Transport.Jobs.NotificationSubscriptionProducerJob do
  @moduledoc """
  Job in charge of updating `NotificationSubscription` objects to set the role
  to `producer` for relevant contacts (they are members of an organization for which
  we have datasets and they are subscribed to).
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    ids =
      DB.NotificationSubscription.base_query()
      |> join(:inner, [notification_subscription: ns], c in assoc(ns, :contact), as: :contact)
      |> join(:inner, [contact: c], c in assoc(c, :organizations), as: :organization)
      |> join(:inner, [notification_subscription: ns, contact: c, organization: o], d in assoc(ns, :dataset),
        on: d.organization_id == o.id,
        as: :dataset
      )
      |> where([notification_subscription: ns], ns.role == :reuser)
      |> select([notification_subscription: ns], ns.id)

    DB.NotificationSubscription.base_query()
    |> where([notification_subscription: ns], ns.id in subquery(ids))
    |> DB.Repo.update_all(set: [role: :producer])

    :ok
  end
end
