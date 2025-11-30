defmodule Transport.Jobs.ResourceUnavailableNotificationJob do
  @moduledoc """
  Job in charge of sending notifications when a dataset has at least a resource
  currently unavailable for at least 6 hours.

  Notifications are sent at the dataset level and are sent again no sooner than
  7 days apart (to avoid potential spamming).

  This job should be scheduled every 30 minutes because it looks at unavailabilities
  that are ongoing since [6h00 ; 6h30].
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]
  import Ecto.Query

  @hours_consecutive_downtime 6
  @nb_days_before_sending_notification_again 7
  @notification_reason Transport.NotificationReason.reason(:resource_unavailable)

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, inserted_at: %DateTime{} = inserted_at}) do
    inserted_at
    |> relevant_unavailabilities()
    |> Enum.each(fn {%DB.Dataset{} = dataset, unavailabilities} ->
      producer_subscriptions = subscriptions(dataset, :producer)
      send_to_producers(producer_subscriptions, dataset, unavailabilities, job_id: job_id)

      dataset
      |> subscriptions(:reuser)
      |> send_to_reusers(dataset, unavailabilities,
        producer_warned: not Enum.empty?(producer_subscriptions),
        job_id: job_id
      )
    end)
  end

  defp send_to_reusers(subscriptions, %DB.Dataset{} = dataset, unavailabilities,
         producer_warned: producer_warned,
         job_id: job_id
       ) do
    Enum.each(subscriptions, fn subscription ->
      send_mail(subscription,
        dataset: dataset,
        hours_consecutive_downtime: @hours_consecutive_downtime,
        producer_warned: producer_warned,
        resource_titles: Enum.map_join(unavailabilities, ", ", &resource_title/1),
        unavailabilities: unavailabilities,
        job_id: job_id
      )
    end)
  end

  defp send_to_producers(subscriptions, %DB.Dataset{} = dataset, unavailabilities, job_id: job_id) do
    Enum.each(subscriptions, fn subscription ->
      send_mail(subscription,
        dataset: dataset,
        hours_consecutive_downtime: @hours_consecutive_downtime,
        deleted_recreated_on_datagouv: deleted_and_recreated_resource_hosted_on_datagouv(dataset, unavailabilities),
        resource_titles: Enum.map_join(unavailabilities, ", ", &resource_title/1),
        unavailabilities: unavailabilities,
        job_id: job_id
      )
    end)
  end

  defp send_mail(
         %DB.NotificationSubscription{role: role, contact: %DB.Contact{} = contact} = subscription,
         args
       ) do
    {:ok, _} = contact |> Transport.UserNotifier.resource_unavailable(role, args) |> Transport.Mailer.deliver()
    save_notification(subscription, args)
  end

  defp save_notification(%DB.NotificationSubscription{role: :reuser} = subscription, args) do
    %DB.Dataset{} = dataset = Keyword.fetch!(args, :dataset)
    unavailabilities = Keyword.fetch!(args, :unavailabilities)

    DB.Notification.insert!(dataset, subscription, %{
      resource_ids:
        Enum.map(unavailabilities, fn %DB.ResourceUnavailability{resource: %DB.Resource{id: resource_id}} ->
          resource_id
        end),
      producer_warned: Keyword.fetch!(args, :producer_warned),
      hours_consecutive_downtime: Keyword.fetch!(args, :hours_consecutive_downtime),
      job_id: Keyword.fetch!(args, :job_id)
    })
  end

  defp save_notification(%DB.NotificationSubscription{role: :producer} = subscription, args) do
    %DB.Dataset{} = dataset = Keyword.fetch!(args, :dataset)
    unavailabilities = Keyword.fetch!(args, :unavailabilities)

    DB.Notification.insert!(dataset, subscription, %{
      resource_ids:
        Enum.map(unavailabilities, fn %DB.ResourceUnavailability{resource: %DB.Resource{id: resource_id}} ->
          resource_id
        end),
      deleted_recreated_on_datagouv: Keyword.fetch!(args, :deleted_recreated_on_datagouv),
      hours_consecutive_downtime: Keyword.fetch!(args, :hours_consecutive_downtime),
      job_id: Keyword.fetch!(args, :job_id)
    })
  end

  @doc """
  Detects when the producer deleted and recreated just after a resource hosted on data.gouv.fr.
  Best practice: upload a new version of the file, keep the same datagouv's resource.

  Detected if:
  - a resource hosted on datagouv is unavailable (ie it was deleted)
  - call the API now and see that a resource hosted on datagouv has been created recently
  """
  def deleted_and_recreated_resource_hosted_on_datagouv(%DB.Dataset{} = dataset, unavailabilities) do
    hosted_on_datagouv = Enum.any?(unavailabilities, &DB.Resource.hosted_on_datagouv?(&1.resource))
    hosted_on_datagouv and created_resource_hosted_on_datagouv_recently?(dataset)
  end

  def created_resource_hosted_on_datagouv_recently?(%DB.Dataset{datagouv_id: datagouv_id}) do
    case Datagouvfr.Client.Datasets.get(datagouv_id) do
      {:ok, %{"resources" => resources}} ->
        dt_limit = DateTime.utc_now() |> DateTime.add(-12, :hour)

        Enum.any?(resources, fn %{"created_at" => created_at, "url" => url} ->
          is_recent = created_at |> parse_datetime() |> DateTime.compare(dt_limit) == :gt
          is_recent and DB.Resource.hosted_on_datagouv?(url)
        end)

      _ ->
        false
    end
  end

  defp parse_datetime(value) do
    {:ok, datetime, 0} = DateTime.from_iso8601(value)
    datetime
  end

  def relevant_unavailabilities(%DateTime{} = inserted_at) do
    datetime_lower_limit = inserted_at |> DateTime.add(-@hours_consecutive_downtime * 60 - 30, :minute)
    datetime_upper_limit = inserted_at |> DateTime.add(-@hours_consecutive_downtime, :hour)

    DB.ResourceUnavailability
    |> where([ru], is_nil(ru.end) and ru.start >= ^datetime_lower_limit and ru.start <= ^datetime_upper_limit)
    |> preload([:resource, resource: [:dataset]])
    |> DB.Repo.all()
    |> Enum.group_by(& &1.resource.dataset)
    |> Enum.sort_by(&elem(&1, 0).id)
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

  defp resource_title(%DB.ResourceUnavailability{resource: %DB.Resource{title: title}}) do
    title
  end
end
