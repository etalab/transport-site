defmodule Transport.Jobs.VisitStatisticsBase do
  @moduledoc """
  Shared functionality for visit statistics notification jobs.

  This module provides common logic for jobs that notify producers about
  statistics availability (download statistics, proxy statistics, etc.).

  The jobs using this module need to provide:
  - A notification reason atom
  - A resource filter function (e.g., &DB.Resource.hosted_on_datagouv?/1)
  - An email notifier function (e.g., &Transport.UserNotifier.visit_download_statistics/1)
  """
  import Ecto.Query

  @doc """
  Main job execution logic.

  ## Parameters
  - `scheduled_at`: DateTime when the job was scheduled
  - `notification_reason`: Atom representing the notification reason
  - `resource_filter_fn`: Function to filter relevant resources
  - `email_notifier_fn`: Function to create the email notification
  """
  def perform_job(
        %DateTime{} = scheduled_at,
        notification_reason,
        resource_filter_fn,
        email_notifier_fn
      ) do
    already_sent_emails = email_addresses_already_sent(scheduled_at, notification_reason)

    relevant_contacts(resource_filter_fn)
    |> Enum.reject(&(&1.email in already_sent_emails))
    |> Enum.each(fn %DB.Contact{} = contact ->
      contact
      |> save_notification(notification_reason)
      |> email_notifier_fn.()
      |> Transport.Mailer.deliver()
    end)
  end

  @doc """
  Finds all contacts relevant for the given resource filter.
  """
  def relevant_contacts(resource_filter_fn) do
    DB.Resource
    |> select([r], [:url, :dataset_id])
    |> preload(dataset: [organization_object: :contacts])
    |> DB.Repo.all()
    |> Enum.filter(resource_filter_fn)
    |> Enum.flat_map(& &1.dataset.organization_object.contacts)
    |> Enum.uniq()
  end

  @doc """
  Gets email addresses that have already been sent this notification in the last 30 days.
  """
  def email_addresses_already_sent(%DateTime{} = scheduled_at, notification_reason) do
    datetime_limit = DateTime.add(scheduled_at, -30, :day)

    DB.Notification.base_query()
    |> where([notification: n], n.inserted_at >= ^datetime_limit and n.reason == ^notification_reason)
    |> select([notification: n], n.email)
    |> distinct(true)
    |> DB.Repo.all()
  end

  @doc """
  Saves a notification record for tracking purposes.
  """
  def save_notification(%DB.Contact{id: contact_id, email: email} = contact, notification_reason) do
    DB.Notification.insert!(%{
      contact_id: contact_id,
      email: email,
      reason: notification_reason,
      role: :producer
    })

    contact
  end
end
