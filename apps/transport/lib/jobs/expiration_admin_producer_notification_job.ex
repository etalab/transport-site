defmodule Transport.Jobs.ExpirationAdminProducerNotificationJob do
  @moduledoc """
  This module is in charge of sending notifications to admins and producers when data is outdated.
  It is similar to `Transport.Jobs.ExpirationNotificationJob`, dedicated to reusers.
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]

  @type delay_and_records :: {integer(), [{DB.Dataset.t(), [DB.Resource.t()]}]}
  @expiration_reason Transport.NotificationReason.reason(:expiration)

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id}) do
    outdated_data(job_id)
    :ok
  end

  def outdated_data(job_id) do
    for delay <- Transport.Expiration.producer_admin_delays(),
        date = Date.add(Date.utc_today(), delay) do
      {delay, Transport.Expiration.datasets_with_resources_expiring_on(date)}
    end
    |> Enum.reject(fn {_, records} -> Enum.empty?(records) end)
    |> send_outdated_data_admin_mail()
    |> Enum.map(&send_outdated_data_producer_notifications(&1, job_id))
  end

  # A different email is sent to producers for every delay, containing all datasets expiring on this given delay
  @spec send_outdated_data_producer_notifications(delay_and_records(), integer()) :: :ok
  def send_outdated_data_producer_notifications({delay, records}, job_id) do
    Enum.each(records, fn {%DB.Dataset{} = dataset, resources} ->
      @expiration_reason
      |> DB.NotificationSubscription.subscriptions_for_reason_dataset_and_role(dataset, :producer)
      |> Enum.each(fn %DB.NotificationSubscription{contact: %DB.Contact{} = contact} = subscription ->
        contact
        |> Transport.UserNotifier.expiration_producer(dataset, resources, delay)
        |> Transport.Mailer.deliver()

        DB.Notification.insert!(dataset, subscription, %{delay: delay, job_id: job_id})
      end)
    end)
  end

  @spec send_outdated_data_admin_mail([delay_and_records()]) :: [delay_and_records()]
  defp send_outdated_data_admin_mail([] = _records), do: []

  defp send_outdated_data_admin_mail(records) do
    Transport.AdminNotifier.expiration(records)
    |> Transport.Mailer.deliver()

    records
  end
end
