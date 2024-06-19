defmodule Transport.Jobs.MultiValidationWithErrorNotificationJob do
  @moduledoc """
  Job in charge of sending notifications when a dataset has at least a resource,
  which got updated recently, with a validation error.

  It ignores validations carried out on real-time resources.

  Notifications are sent at the dataset level.

  This job should be scheduled every 30 minutes because it looks at validations
  that have been created in the last 30 minutes.
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]
  import Ecto.Query

  @nb_days_before_sending_notification_again 7
  @notification_reason DB.NotificationSubscription.reason(:dataset_with_error)
  @enabled_validators [
    Transport.Validators.GTFSTransport,
    Transport.Validators.TableSchema,
    Transport.Validators.EXJSONSchema
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, inserted_at: %DateTime{} = inserted_at}) do
    inserted_at
    |> relevant_validations()
    |> Enum.each(fn {%DB.Dataset{} = dataset, multi_validations} ->
      producer_subscriptions = dataset |> subscriptions(:producer)
      send_to_producers(producer_subscriptions, dataset, multi_validations, job_id: job_id)

      dataset
      |> subscriptions(:reuser)
      |> send_to_reusers(dataset, producer_warned: not Enum.empty?(producer_subscriptions), job_id: job_id)
    end)
  end

  defp send_to_reusers(subscriptions, %DB.Dataset{} = dataset, producer_warned: producer_warned, job_id: job_id) do
    Enum.each(
      subscriptions,
      &send_mail(&1, dataset: dataset, producer_warned: producer_warned, job_id: job_id)
    )
  end

  defp send_to_producers(subscriptions, %DB.Dataset{} = dataset, multi_validations, job_id: job_id) do
    Enum.each(
      subscriptions,
      &send_mail(&1,
        dataset: dataset,
        resources: Enum.map(multi_validations, fn mv -> mv.resource_history.resource end),
        job_id: job_id
      )
    )
  end

  defp send_mail(
         %DB.NotificationSubscription{role: role, contact: %DB.Contact{} = contact} = subscription,
         [{:dataset, %DB.Dataset{} = dataset} | _] = args
       ) do
    Transport.UserNotifier.multi_validation_with_error_notification(contact, role, args)
    |> Transport.Mailer.deliver()

    save_notification(dataset, subscription, args)
  end

  defp save_notification(%DB.Dataset{} = dataset, %DB.NotificationSubscription{role: :reuser} = subscription, args) do
    producer_warned = Keyword.fetch!(args, :producer_warned)
    job_id = Keyword.fetch!(args, :job_id)
    DB.Notification.insert!(dataset, subscription, %{producer_warned: producer_warned, job_id: job_id})
  end

  defp save_notification(%DB.Dataset{} = dataset, %DB.NotificationSubscription{role: :producer} = subscription, args) do
    resources = Keyword.fetch!(args, :resources)
    job_id = Keyword.fetch!(args, :job_id)

    DB.Notification.insert!(dataset, subscription, %{
      resource_ids: Enum.map(resources, fn %DB.Resource{id: resource_id} -> resource_id end),
      resource_formats: Enum.map(resources, fn %DB.Resource{format: format} -> format end),
      job_id: job_id
    })
  end

  def relevant_validations(%DateTime{} = inserted_at) do
    datetime_limit = inserted_at |> DateTime.add(-30, :minute)
    validator_names = Enum.map(@enabled_validators, & &1.validator_name())

    DB.MultiValidation.base_query()
    |> where([mv], mv.max_error in ["Error", "Fatal"] or fragment("?->>'has_errors' = 'true'", mv.result))
    |> where(
      [mv],
      not is_nil(mv.resource_history_id) and mv.validator in ^validator_names and mv.inserted_at >= ^datetime_limit
    )
    |> preload(resource_history: [resource: [:dataset]])
    |> DB.Repo.all()
    |> Enum.group_by(& &1.resource_history.resource.dataset)
  end

  defp subscriptions(%DB.Dataset{} = dataset, role) do
    @notification_reason
    |> DB.NotificationSubscription.subscriptions_for_reason_dataset_and_role(dataset, role)
    |> reject_already_sent(dataset)
  end

  defp reject_already_sent(notification_subscriptions, %DB.Dataset{} = dataset) do
    already_sent_emails = email_addresses_already_sent(dataset)

    Enum.reject(notification_subscriptions, fn %DB.NotificationSubscription{contact: %DB.Contact{email: email}} ->
      email in already_sent_emails
    end)
  end

  def email_addresses_already_sent(%DB.Dataset{id: dataset_id}) do
    datetime_limit = DateTime.utc_now() |> DateTime.add(-@nb_days_before_sending_notification_again, :day)

    DB.Notification
    |> where([n], n.inserted_at >= ^datetime_limit and n.dataset_id == ^dataset_id and n.reason == @notification_reason)
    |> select([n], n.email)
    |> distinct(true)
    |> DB.Repo.all()
  end
end
