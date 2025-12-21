defmodule Transport.Jobs.MultiValidationWithErrorNotificationJob do
  @moduledoc """
  Job in charge of sending notifications to subscribers when resources have validation errors.

  It has a list of enabled validators and is capable of handling static and real-time data.
  The delay to wait before sending a notification again can vary by validator (it will typically
  be longer for real-time as it takes more time to fix these errors).

  This job should be scheduled every 30 minutes because it looks at validations
  that have been created in the last 30 minutes.
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]
  import Ecto.Query

  @notification_reason Transport.NotificationReason.reason(:dataset_with_error)
  @static_data_validators [
    Transport.Validators.GTFSTransport,
    Transport.Validators.TableSchema,
    Transport.Validators.EXJSONSchema,
    Transport.Validators.MobilityDataGTFSValidator
  ]
  @realtime_data_validators [
    Transport.Validators.GBFSValidator
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, inserted_at: %DateTime{} = inserted_at}) do
    relevant_validations(inserted_at)
    |> Enum.each(&send_notifications_for_dataset(&1, job_id))
  end

  @doc """
  Send notification errors for a dataset.
  Notifications are grouped by validator because the sending delay window is different for each validator
  (static data VS real time data for example).
  """
  def send_notifications_for_dataset({%DB.Dataset{} = dataset, multi_validations}, job_id) do
    multi_validations
    |> Enum.group_by(& &1.validator)
    |> Enum.each(fn {validator_name, errors} ->
      producer_subscriptions = dataset |> subscriptions(:producer, validator_name)
      send_to_producers(producer_subscriptions, dataset, errors, validator_name: validator_name, job_id: job_id)

      dataset
      |> subscriptions(:reuser, validator_name)
      |> send_to_reusers(dataset,
        producer_warned: not Enum.empty?(producer_subscriptions),
        validator_name: validator_name,
        job_id: job_id
      )
    end)
  end

  defp send_to_reusers(subscriptions, %DB.Dataset{} = dataset,
         producer_warned: producer_warned,
         validator_name: validator_name,
         job_id: job_id
       ) do
    Enum.each(
      subscriptions,
      &send_mail(&1, dataset: dataset, producer_warned: producer_warned, validator_name: validator_name, job_id: job_id)
    )
  end

  defp send_to_producers(subscriptions, %DB.Dataset{} = dataset, multi_validations,
         validator_name: validator_name,
         job_id: job_id
       ) do
    Enum.each(
      subscriptions,
      &send_mail(&1,
        dataset: dataset,
        resources: Enum.map(multi_validations, fn %DB.MultiValidation{} = mv -> multi_validation_to_resource(mv) end),
        validator_name: validator_name,
        job_id: job_id
      )
    )
  end

  defp multi_validation_to_resource(%DB.MultiValidation{
         resource_history: %DB.ResourceHistory{resource: %DB.Resource{} = resource}
       }),
       do: resource

  defp multi_validation_to_resource(%DB.MultiValidation{resource: %DB.Resource{} = resource}), do: resource

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
    validator_name = Keyword.fetch!(args, :validator_name)

    DB.Notification.insert!(dataset, subscription, %{
      producer_warned: producer_warned,
      validator_name: validator_name,
      job_id: job_id
    })
  end

  defp save_notification(%DB.Dataset{} = dataset, %DB.NotificationSubscription{role: :producer} = subscription, args) do
    resources = Keyword.fetch!(args, :resources)
    job_id = Keyword.fetch!(args, :job_id)
    validator_name = Keyword.fetch!(args, :validator_name)

    DB.Notification.insert!(dataset, subscription, %{
      resource_ids: Enum.map(resources, fn %DB.Resource{id: resource_id} -> resource_id end),
      resource_formats: Enum.map(resources, fn %DB.Resource{format: format} -> format end),
      validator_name: validator_name,
      job_id: job_id
    })
  end

  def relevant_validations(%DateTime{} = inserted_at) do
    datetime_limit = inserted_at |> DateTime.add(-30, :minute)

    Map.merge(
      relevant_static_validations(datetime_limit),
      relevant_realtime_validations(datetime_limit),
      fn %DB.Dataset{}, mv_1, mv_2 -> mv_1 ++ mv_2 end
    )
    |> Enum.sort_by(fn {%DB.Dataset{id: id}, _} -> id end)
  end

  defp relevant_static_validations(%DateTime{} = datetime_limit) do
    validator_names = Enum.map(@static_data_validators, & &1.validator_name())

    DB.MultiValidation.base_query()
    |> where(
      [multi_validation: mv],
      mv.max_error in ["Error", "Fatal", "ERROR"] or fragment("?->>'has_errors' = 'true'", mv.result)
    )
    |> where(
      [multi_validation: mv],
      not is_nil(mv.resource_history_id) and mv.validator in ^validator_names and mv.inserted_at >= ^datetime_limit
    )
    |> preload(resource_history: [resource: [:dataset]])
    |> DB.Repo.all()
    |> Enum.group_by(& &1.resource_history.resource.dataset)
  end

  defp relevant_realtime_validations(%DateTime{} = datetime_limit) do
    validator_names = Enum.map(@realtime_data_validators, & &1.validator_name())

    DB.MultiValidation.base_query()
    |> where([multi_validation: mv], fragment("?->>'has_errors' = 'true'", mv.result))
    |> where(
      [multi_validation: mv],
      is_nil(mv.resource_history_id) and mv.validator in ^validator_names and mv.inserted_at >= ^datetime_limit
    )
    |> preload(resource: :dataset)
    |> DB.Repo.all()
    |> Enum.group_by(& &1.resource.dataset)
  end

  defp subscriptions(%DB.Dataset{} = dataset, role, validator_name) do
    @notification_reason
    |> DB.NotificationSubscription.subscriptions_for_reason_dataset_and_role(dataset, role)
    |> reject_already_sent(dataset, validator_name)
  end

  defp reject_already_sent(notification_subscriptions, %DB.Dataset{} = dataset, validator_name) do
    already_sent_emails = email_addresses_already_sent(dataset, validator_name)

    Enum.reject(notification_subscriptions, fn %DB.NotificationSubscription{contact: %DB.Contact{email: email}} ->
      email in already_sent_emails
    end)
  end

  def all_validators, do: @static_data_validators ++ @realtime_data_validators

  @doc """
  iex> sending_delay_by_validator(Transport.Validators.GBFSValidator.validator_name())
  {30, :day}
  iex> all_validators() |> Enum.map(& &1.validator_name()) |> Enum.each(&sending_delay_by_validator/1)
  :ok
  """
  @spec sending_delay_by_validator(binary()) :: {pos_integer(), :day}
  def sending_delay_by_validator(validator) do
    %{
      Transport.Validators.GTFSTransport => {7, :day},
      Transport.Validators.TableSchema => {7, :day},
      Transport.Validators.EXJSONSchema => {7, :day},
      Transport.Validators.MobilityDataGTFSValidator => {7, :day},
      Transport.Validators.GBFSValidator => {30, :day}
    }
    |> Map.new(fn {validator, delay} -> {validator.validator_name(), delay} end)
    |> Map.fetch!(validator)
  end

  def email_addresses_already_sent(%DB.Dataset{id: dataset_id}, validator_name) do
    {delay, unit} = sending_delay_by_validator(validator_name)
    datetime_limit = DateTime.utc_now() |> DateTime.add(-delay, unit)

    DB.Notification.base_query()
    |> where(
      [notification: n],
      n.inserted_at >= ^datetime_limit and n.dataset_id == ^dataset_id and n.reason == @notification_reason
    )
    |> where(
      [notification: n],
      # validator information is not filled (legacy notifications) OR
      # notifications sent related to the given validator
      is_nil(n.payload) or not fragment("? \\? 'validator_name'", n.payload) or
        fragment("?->'validator_name' = ?", n.payload, ^validator_name)
    )
    |> select([notification: n], n.email)
    |> distinct(true)
    |> DB.Repo.all()
  end
end
