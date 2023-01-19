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
          """
          Bonjour,

          Les ressources #{Enum.map_join(unavailabilities, ", ", &resource_title/1)} dans votre jeu de données #{dataset_url(dataset)} ne sont plus disponibles au téléchargement depuis plus de #{@hours_consecutive_downtime}h.

          Ces erreurs empêchent la réutilisation de vos données.

          Nous vous invitons à corriger l'accès de vos données dès que possible.

          Nous restons disponible pour vous accompagner si besoin.

          Merci par avance pour votre action,

          À bientôt,

          L'équipe du PAN
          """,
          ""
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
    Transport.Notifications.config()
    |> Transport.Notifications.emails_for_reason(@notification_reason, dataset)
    |> MapSet.new()
  end

  defp dataset_url(%DB.Dataset{slug: slug, custom_title: custom_title}) do
    url = TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, slug)

    "#{custom_title} — #{url}"
  end

  defp resource_title(%DB.ResourceUnavailability{resource: %DB.Resource{title: title}}) do
    title
  end
end
