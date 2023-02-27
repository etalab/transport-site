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

  @nb_days_before_sending_notification_again 15
  @notification_reason :dataset_with_error
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
      dataset
      |> emails_list()
      |> MapSet.difference(notifications_sent_recently(dataset))
      |> Enum.each(fn email ->
        Transport.EmailSender.impl().send_mail(
          "transport.data.gouv.fr",
          Application.get_env(:transport, :contact_email),
          email,
          Application.get_env(:transport, :contact_email),
          "Erreurs détectées dans le jeu de données #{dataset.custom_title}",
          """
          Bonjour,

          Des erreurs bloquantes ont été détectées dans votre jeu de données #{dataset_url(dataset)}. Ces erreurs empêchent la réutilisation de vos données.

          Nous vous invitons à les corriger en vous appuyant sur les rapports de validation suivants :
          #{Enum.map_join(multi_validations, "\n", &resource_link/1)}

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

  defp emails_list(%DB.Dataset{} = dataset) do
    @notification_reason
    |> DB.NotificationSubscription.subscriptions_for_reason(dataset)
    |> DB.NotificationSubscription.subscriptions_to_emails()
    |> MapSet.new()
  end

  defp dataset_url(%DB.Dataset{slug: slug, custom_title: custom_title}) do
    url = TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, slug)

    "#{custom_title} — #{url}"
  end

  defp resource_link(%DB.MultiValidation{
         resource_history: %DB.ResourceHistory{resource: %DB.Resource{id: id, title: title}}
       }) do
    url = TransportWeb.Router.Helpers.resource_url(TransportWeb.Endpoint, :details, id) <> "#validation-report"

    "* #{title} — #{url}"
  end
end
