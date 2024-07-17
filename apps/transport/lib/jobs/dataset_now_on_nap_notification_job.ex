defmodule Transport.Jobs.DatasetNowOnNAPNotificationJob do
  @moduledoc """
  Job in charge of sending a welcome notification to producers when a dataset has been added on the NAP.
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"], unique: [period: :infinity]
  import Ecto.Query

  @notification_reason Transport.NotificationReason.reason(:dataset_now_on_nap)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"dataset_id" => dataset_id}, id: job_id}) do
    dataset = DB.Repo.get!(DB.Dataset, dataset_id)

    # Identify producer subscriptions for this dataset and send a welcome email
    # to each contact, only once per contact even if they have subscriptions
    # for various reasons.
    dataset
    |> DB.NotificationSubscription.subscriptions_for_dataset_and_role(:producer)
    |> Enum.uniq_by(fn %DB.NotificationSubscription{contact_id: contact_id} -> contact_id end)
    |> reject_already_sent(dataset)
    |> Enum.each(fn %DB.NotificationSubscription{contact: %DB.Contact{} = contact} ->
      Transport.UserNotifier.dataset_now_on_nap(contact, dataset)
      |> Transport.Mailer.deliver()

      save_notification(contact, dataset)
    end)

    Oban.Notifier.notify(Oban, :gossip, %{complete: job_id})
  end

  defp save_notification(%DB.Contact{id: contact_id, email: email}, %DB.Dataset{id: dataset_id}) do
    DB.Notification.insert!(%{
      reason: @notification_reason,
      dataset_id: dataset_id,
      email: email,
      contact_id: contact_id,
      role: :producer
    })
  end

  defp reject_already_sent(notification_subscriptions, %DB.Dataset{} = dataset) do
    already_sent_emails = email_addresses_already_sent(dataset)

    Enum.reject(notification_subscriptions, fn %DB.NotificationSubscription{contact: %DB.Contact{email: email}} ->
      email in already_sent_emails
    end)
  end

  @spec email_addresses_already_sent(DB.Dataset.t()) :: MapSet.t()
  defp email_addresses_already_sent(%DB.Dataset{id: dataset_id}) do
    DB.Notification
    |> where([n], n.dataset_id == ^dataset_id and n.reason == @notification_reason)
    |> select([n], n.email)
    |> DB.Repo.all()
    |> MapSet.new()
  end
end
