defmodule Transport.Jobs.MultiValidationWithErrorNotificationJob do
  @moduledoc """
  An Oban worker responsible for notifying subscribers (Producers and Reusers)
  when datasets fail validation checks.

  This job implements a "cooling-off" period and multi-stage notification logic
  to prevent spam while ensuring critical data errors are addressed.

  ## Orchestration & Scheduling
  * **Initial Run:** Should be scheduled every **30 minutes**. It scans for new
    `DB.MultiValidation` records created within the last 30 minutes.
  * **Recursive Retries:** If errors persist, the job re-enqueues itself with a
    specific delay based on the validator type (e.g., 7 days for static data,
    30 days for real-time data).

  ## Notification Logic
  The job distinguishes between two roles defined in `DB.NotificationSubscription`:

  1.  **Producers:** Always notified when a validation error occurs, provided the
      cooling-off period has passed. They receive specific details about the
      resource and the validator that failed.
  2.  **Reusers:** Notified only on the **first attempt** (`attempt == 1`) to
      alert them of potential quality issues in the data they consume.

  ## Validator Types
  The job handles two distinct categories of validators:

  * **Static Data Validators:** (e.g., GTFS, TableSchema). Matches records with
      severity "Error", "Fatal", or explicit "has_errors" flags.
  * **Real-time Data Validators:** (e.g., GTFS-RT). Includes a threshold
      mechanism (`@gtfs_rt_errors_threshold`). For GTFS-RT, notifications are
      only triggered if the sum of high-severity error counts exceeds the threshold.

  ## Suppression (Anti-Spam)
  Before sending an email, the job checks the `DB.Notification` history. If a
  notification for the same dataset and validator was sent within the
  `sending_delay_by_validator/1` window, the email is suppressed.

  ## Expected Arguments
  * `%{"dataset_id" => id, "multi_validation_ids" => [...], "attempt" => n}`
      Used for scheduled follow-ups/retries.
  * `%{}`
      Used for the primary 30-minute recurring scan.
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]
  import Ecto.Query

  @notification_reason Transport.NotificationReason.reason(:dataset_with_error)

  @gtfs_rt_validator Transport.Validators.GTFSRT.validator_name()
  @gtfs_rt_errors_threshold 50

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{"dataset_id" => dataset_id, "multi_validation_ids" => multi_validation_ids, "attempt" => attempt}
      }) do
    dataset = DB.Repo.get!(DB.Dataset, dataset_id)

    filtered_validations =
      DB.MultiValidation.dataset_latest_validation(dataset_id, static_data_validators())
      |> Map.values()
      |> List.flatten()
      |> Enum.filter(fn %DB.MultiValidation{id: id} -> id in multi_validation_ids end)
      |> Enum.map(&DB.Repo.preload(&1, resource_history: [resource: [:dataset]]))

    validations = [{dataset, filtered_validations}]

    validations |> Enum.each(&send_notifications_for_dataset(&1, job_id: job_id, attempt: attempt))
    enqueue_next_job(validations, attempt)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, inserted_at: %DateTime{} = inserted_at}) do
    attempt = 1
    validations = relevant_validations(inserted_at)
    validations |> Enum.each(&send_notifications_for_dataset(&1, job_id: job_id, attempt: attempt))

    enqueue_next_job(validations, attempt)
  end

  defp enqueue_next_job(validations, attempt) do
    validator_names = Enum.map(static_data_validators(), & &1.validator_name())

    validations
    |> Enum.map(fn {%DB.Dataset{} = dataset, multi_validations} ->
      {dataset,
       Enum.filter(multi_validations, fn %DB.MultiValidation{validator: validator} -> validator in validator_names end)}
    end)
    |> Enum.reject(fn {_, mv} -> Enum.empty?(mv) end)
    |> Enum.each(fn {%DB.Dataset{} = dataset, multi_validations} ->
      [delay] = Enum.map(multi_validations, &sending_delay_by_validator(&1.validator)) |> Enum.uniq()

      new(%{dataset_id: dataset.id, multi_validation_ids: Enum.map(multi_validations, & &1.id), attempt: attempt + 1},
        schedule_in: delay
      )
      |> Oban.insert!()
    end)
  end

  @doc """
  Send notification errors for a dataset.
  Notifications are grouped by validator because the sending delay window is different for each validator
  (static data VS real time data for example).
  """
  def send_notifications_for_dataset({%DB.Dataset{} = dataset, multi_validations}, job_id: job_id, attempt: attempt) do
    multi_validations
    |> Enum.group_by(& &1.validator)
    |> Enum.each(fn {validator_name, errors} ->
      producer_subscriptions = dataset |> subscriptions(:producer, validator_name)

      send_to_producers(producer_subscriptions, dataset, errors,
        validator_name: validator_name,
        job_id: job_id,
        attempt: attempt
      )

      if attempt == 1 do
        dataset
        |> subscriptions(:reuser, validator_name)
        |> send_to_reusers(dataset,
          producer_warned: not Enum.empty?(producer_subscriptions),
          validator_name: validator_name,
          job_id: job_id,
          attempt: attempt
        )
      end
    end)
  end

  defp send_to_reusers(subscriptions, %DB.Dataset{} = dataset,
         producer_warned: producer_warned,
         validator_name: validator_name,
         job_id: job_id,
         attempt: attempt
       ) do
    Enum.each(
      subscriptions,
      &send_mail(&1,
        dataset: dataset,
        producer_warned: producer_warned,
        validator_name: validator_name,
        job_id: job_id,
        attempt: attempt
      )
    )
  end

  defp send_to_producers(subscriptions, %DB.Dataset{} = dataset, multi_validations,
         validator_name: validator_name,
         job_id: job_id,
         attempt: attempt
       ) do
    Enum.each(
      subscriptions,
      &send_mail(&1,
        dataset: dataset,
        resources: Enum.map(multi_validations, fn %DB.MultiValidation{} = mv -> multi_validation_to_resource(mv) end),
        validator_name: validator_name,
        job_id: job_id,
        attempt: attempt
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
    attempt = Keyword.fetch!(args, :attempt)

    DB.Notification.insert!(dataset, subscription, %{
      producer_warned: producer_warned,
      validator_name: validator_name,
      job_id: job_id,
      attempt: attempt
    })
  end

  defp save_notification(%DB.Dataset{} = dataset, %DB.NotificationSubscription{role: :producer} = subscription, args) do
    resources = Keyword.fetch!(args, :resources)
    job_id = Keyword.fetch!(args, :job_id)
    validator_name = Keyword.fetch!(args, :validator_name)
    attempt = Keyword.fetch!(args, :attempt)

    DB.Notification.insert!(dataset, subscription, %{
      resource_ids: Enum.map(resources, fn %DB.Resource{id: resource_id} -> resource_id end),
      resource_formats: Enum.map(resources, fn %DB.Resource{format: format} -> format end),
      validator_name: validator_name,
      job_id: job_id,
      attempt: attempt
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
    validator_names = Enum.map(static_data_validators(), & &1.validator_name())

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
    validator_names = Enum.map(realtime_data_validators(), & &1.validator_name())

    DB.MultiValidation.with_result()
    |> where([multi_validation: mv], fragment("?->>'has_errors' = 'true'", mv.result))
    |> where(
      [multi_validation: mv],
      is_nil(mv.resource_history_id) and mv.validator in ^validator_names and mv.inserted_at >= ^datetime_limit
    )
    |> preload(resource: :dataset)
    |> DB.Repo.all()
    |> Enum.filter(&relevant_realtime_validation?/1)
    |> Enum.group_by(& &1.resource.dataset)
  end

  def relevant_realtime_validation?(%DB.MultiValidation{validator: @gtfs_rt_validator, result: %{"errors" => errors}}) do
    high_severity_errors = ["E003", "E004", "E011", "E034"]

    errors
    |> Enum.filter(&(&1["error_id"] in high_severity_errors))
    |> Enum.sum_by(& &1["errors_count"]) >= @gtfs_rt_errors_threshold
  end

  def relevant_realtime_validation?(%DB.MultiValidation{}), do: true

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

  def all_validators, do: static_data_validators() ++ realtime_data_validators()

  @doc """
  iex> sending_delay_by_validator(Transport.Validators.GBFSValidator.validator_name())
  {30, :day}
  iex> all_validators() |> Enum.map(& &1.validator_name()) |> Enum.each(&sending_delay_by_validator/1)
  :ok
  iex> static_data_validators() |> Enum.map(& sending_delay_by_validator(&1.validator_name())) |> Enum.uniq()
  [{7, :day}]
  """
  @spec sending_delay_by_validator(binary()) :: {pos_integer(), :day}
  def sending_delay_by_validator(validator) do
    %{
      Transport.Validators.GTFSTransport => {7, :day},
      Transport.Validators.TableSchema => {7, :day},
      Transport.Validators.JSONSchema => {7, :day},
      Transport.Validators.MobilityDataGTFSValidator => {7, :day},
      Transport.Validators.GBFSValidator => {30, :day},
      Transport.Validators.GTFSRT => {30, :day}
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

  def static_data_validators,
    do: Transport.ValidatorsSelection.validators_for_feature(:multi_validation_with_error_static_validators)

  def realtime_data_validators,
    do: Transport.ValidatorsSelection.validators_for_feature(:multi_validation_with_error_realtime_validators)
end
