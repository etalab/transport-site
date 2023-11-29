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
  @notification_reason DB.NotificationSubscription.reason(:resource_unavailable)

  @impl Oban.Worker
  def perform(%Oban.Job{inserted_at: %DateTime{} = inserted_at}) do
    inserted_at
    |> relevant_unavailabilities()
    |> Enum.each(fn {%DB.Dataset{} = dataset, unavailabilities} ->
      producer_emails = emails_list(dataset, :producer)
      send_to_producers(producer_emails, dataset, unavailabilities)

      reuser_emails = emails_list(dataset, :reuser)
      send_to_reusers(reuser_emails, dataset, unavailabilities, producer_warned: not Enum.empty?(producer_emails))
    end)
  end

  defp send_to_reusers(emails, %DB.Dataset{} = dataset, unavailabilities, producer_warned: producer_warned) do
    Enum.each(emails, fn email ->
      send_mail(email, :reuser,
        dataset: dataset,
        dataset_url: dataset_url(dataset),
        hours_consecutive_downtime: @hours_consecutive_downtime,
        producer_warned: producer_warned,
        resource_titles: Enum.map_join(unavailabilities, ", ", &resource_title/1)
      )
    end)
  end

  defp send_to_producers(emails, dataset, unavailabilities) do
    Enum.each(emails, fn email ->
      send_mail(email, :producer,
        dataset: dataset,
        hours_consecutive_downtime: @hours_consecutive_downtime,
        deleted_recreated_on_datagouv: deleted_and_recreated_resource_hosted_on_datagouv(dataset, unavailabilities),
        resource_titles: Enum.map_join(unavailabilities, ", ", &resource_title/1)
      )
    end)
  end

  defp send_mail(email, role, args) do
    dataset = Keyword.fetch!(args, :dataset)

    Transport.EmailSender.impl().send_mail(
      "transport.data.gouv.fr",
      Application.get_env(:transport, :contact_email),
      email,
      Application.get_env(:transport, :contact_email),
      "Ressources indisponibles dans le jeu de données #{dataset.custom_title}",
      "",
      Phoenix.View.render_to_string(TransportWeb.EmailView, "#{@notification_reason}_#{role}.html", args)
    )

    save_notification(dataset, email)
  end

  def notifications_sent_recently(%DB.Dataset{id: dataset_id}) do
    datetime_limit = DateTime.utc_now() |> DateTime.add(-@nb_days_before_sending_notification_again, :day)

    DB.Notification
    |> where([n], n.inserted_at >= ^datetime_limit and n.dataset_id == ^dataset_id and n.reason == @notification_reason)
    |> select([n], n.email)
    |> DB.Repo.all()
    |> MapSet.new()
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
  end

  defp save_notification(%DB.Dataset{} = dataset, email) do
    DB.Notification.insert!(@notification_reason, dataset, email)
  end

  defp emails_list(%DB.Dataset{} = dataset, role) do
    @notification_reason
    |> DB.NotificationSubscription.subscriptions_for_reason_dataset_and_role(dataset, role)
    |> DB.NotificationSubscription.subscriptions_to_emails()
    |> MapSet.new()
    |> MapSet.difference(notifications_sent_recently(dataset))
  end

  defp resource_title(%DB.ResourceUnavailability{resource: %DB.Resource{title: title}}) do
    title
  end

  defp dataset_url(%DB.Dataset{slug: slug}) do
    TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, slug)
  end
end
