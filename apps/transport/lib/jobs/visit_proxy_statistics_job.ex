defmodule Transport.Jobs.VisitProxyStatisticsJob do
  @moduledoc """
  This job sends emails to producers who are using the transport proxy.
  It tells them to look at their producer space to see statistics.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  @notification_reason :visit_proxy_statistics

  @impl Oban.Worker
  def perform(%Oban.Job{scheduled_at: %DateTime{} = scheduled_at}) do
    already_sent_emails = email_addresses_already_sent(scheduled_at)

    relevant_contacts()
    |> Enum.reject(&(&1.email in already_sent_emails))
    |> Enum.each(fn %DB.Contact{} = contact ->
      contact
      |> save_notification()
      |> Transport.UserNotifier.visit_proxy_statistics()
      |> Transport.Mailer.deliver()
    end)
  end

  def relevant_contacts do
    DB.Resource
    |> select([r], [:url, :dataset_id])
    |> preload(dataset: [organization_object: :contacts])
    |> DB.Repo.all()
    |> Enum.filter(&DB.Resource.served_by_proxy?/1)
    |> Enum.flat_map(& &1.dataset.organization_object.contacts)
    |> Enum.uniq()
  end

  defp save_notification(%DB.Contact{id: contact_id, email: email} = contact) do
    DB.Notification.insert!(%{
      contact_id: contact_id,
      email: email,
      reason: @notification_reason,
      role: :producer
    })

    contact
  end

  def email_addresses_already_sent(%DateTime{} = scheduled_at) do
    datetime_limit = DateTime.add(scheduled_at, -30, :day)

    DB.Notification.base_query()
    |> where([notification: n], n.inserted_at >= ^datetime_limit and n.reason == @notification_reason)
    |> select([notification: n], n.email)
    |> distinct(true)
    |> DB.Repo.all()
  end
end
