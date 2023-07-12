defmodule Transport.Jobs.ResourceUnavailableNotificationJob do
  @moduledoc """
  Job in charge of sending notifications when a dataset has at least a resource
  currently unavailable for at least 6 hours.

  Notifications are sent at the dataset level and are sent again no sooner than
  15 days apart (to avoid potential spamming).

  This job should be scheduled every 30 minutes because it looks at unavailabilities
  that are ongoing since [6h00 ; 6h30].
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]
  import Ecto.Query

  @hours_consecutive_downtime 6
  @nb_days_before_sending_notification_again 15
  @notification_reason :resource_unavailable

  @impl Oban.Worker
  def perform(%Oban.Job{inserted_at: %DateTime{} = inserted_at}) do
    inserted_at
    |> relevant_unavailabilities()
    |> Enum.each(fn {%DB.Dataset{} = dataset, unavailabilities} ->
      dataset
      |> emails_list()
      |> MapSet.difference(notifications_sent_recently(dataset))
      |> Enum.each(fn email ->
        Transport.EmailSender.impl().send_mail(
          "transport.data.gouv.fr",
          Application.get_env(:transport, :contact_email),
          email,
          Application.get_env(:transport, :contact_email),
          "Ressources indisponibles dans le jeu de données #{dataset.custom_title}",
          "",
          Phoenix.View.render_to_string(TransportWeb.EmailView, "resource_unavailable.html",
            dataset: dataset,
            hours_consecutive_downtime: @hours_consecutive_downtime,
            deleted_recreated_on_datagouv: deleted_and_recreated_resource_hosted_on_datagouv(dataset, unavailabilities),
            resource_titles: Enum.map_join(unavailabilities, ", ", &resource_title/1)
          )
        )

        save_notification(dataset, email)
      end)
    end)

    :ok
  end

  defp notifications_sent_recently(%DB.Dataset{id: dataset_id}) do
    datetime_limit = DateTime.utc_now() |> DateTime.add(-@nb_days_before_sending_notification_again, :day)

    DB.Notification
    |> where([n], n.inserted_at >= ^datetime_limit and n.dataset_id == ^dataset_id and n.reason == @notification_reason)
    |> select([n], n.email)
    |> DB.Repo.all()
    |> MapSet.new()
  end

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
  end

  defp save_notification(%DB.Dataset{} = dataset, email) do
    DB.Notification.insert!(@notification_reason, dataset, email)
  end

  defp emails_list(%DB.Dataset{} = dataset) do
    @notification_reason
    |> DB.NotificationSubscription.subscriptions_for_reason(dataset)
    |> DB.NotificationSubscription.subscriptions_to_emails()
    |> MapSet.new()
  end

  defp resource_title(%DB.ResourceUnavailability{resource: %DB.Resource{title: title}}) do
    title
  end
end
