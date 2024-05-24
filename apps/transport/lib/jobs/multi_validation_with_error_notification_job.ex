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
  def perform(%Oban.Job{inserted_at: %DateTime{} = inserted_at}) do
    inserted_at
    |> relevant_validations()
    |> Enum.each(fn {%DB.Dataset{} = dataset, multi_validations} ->
      producer_emails = dataset |> emails_list(:producer)
      send_to_producers(producer_emails, dataset, multi_validations)

      reuser_emails = dataset |> emails_list(:reuser)
      send_to_reusers(reuser_emails, dataset, producer_warned: not Enum.empty?(producer_emails))
    end)
  end

  defp send_to_reusers(emails, %DB.Dataset{} = dataset, producer_warned: producer_warned) do
    Enum.each(
      emails,
      &send_mail(&1, :reuser, dataset: dataset, producer_warned: producer_warned)
    )
  end

  defp send_to_producers(emails, %DB.Dataset{} = dataset, multi_validations) do
    Enum.each(
      emails,
      &send_mail(&1, :producer,
        dataset: dataset,
        resources: Enum.map(multi_validations, fn mv -> mv.resource_history.resource end)
      )
    )
  end

  defp send_mail(email, role, args) do
    email
    |> Transport.UserNotifier.multi_validation_with_error_notification(role, args)
    |> Transport.Mailer.deliver()

    save_notification(Keyword.fetch!(args, :dataset), email)
  end

  def notifications_sent_recently(%DB.Dataset{id: dataset_id}) do
    datetime_limit = DateTime.utc_now() |> DateTime.add(-@nb_days_before_sending_notification_again, :day)

    DB.Notification
    |> where([n], n.inserted_at >= ^datetime_limit and n.dataset_id == ^dataset_id and n.reason == @notification_reason)
    |> select([n], n.email)
    |> DB.Repo.all()
    |> MapSet.new()
  end

  defp save_notification(%DB.Dataset{} = dataset, email) do
    DB.Notification.insert!(@notification_reason, dataset, email)
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

  defp emails_list(%DB.Dataset{} = dataset, role) do
    @notification_reason
    |> DB.NotificationSubscription.subscriptions_for_reason_dataset_and_role(dataset, role)
    |> DB.NotificationSubscription.subscriptions_to_emails()
    |> MapSet.new()
    |> MapSet.difference(notifications_sent_recently(dataset))
  end
end
