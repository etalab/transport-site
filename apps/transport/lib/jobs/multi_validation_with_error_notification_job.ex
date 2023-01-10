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
      |> Enum.each(fn email ->
        Transport.EmailSender.impl().send_mail(
          "transport.data.gouv.fr",
          Application.get_env(:transport, :contact_email),
          email,
          Application.get_env(:transport, :contact_email),
          "Erreur de validation détectée",
          """
          Bonjour,

          Le contenu du jeu de données #{dataset.custom_title} vient de changer.

          Nous avons détecté que des ressources de ce jeu de données comportent des erreurs, ce qui nuit à sa réutilisation.

          Consultez les rapports de validation associés :
          #{Enum.map_join(multi_validations, "\n", &resource_link/1)}

          ---
          Vous pouvez répondre à cet e-mail pour ajuster les notifications que vous recevez ou obtenir de l'aide de notre équipe.
          """,
          ""
        )
      end)
    end)

    :ok
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
    |> preload([:resource, resource: [:dataset]])
    |> DB.Repo.all()
    |> Enum.group_by(& &1.resource.dataset)
  end

  defp emails_list(%DB.Dataset{} = dataset) do
    Transport.Notifications.config()
    |> Transport.Notifications.emails_for_reason(:dataset_with_error, dataset)
  end

  defp resource_link(%DB.MultiValidation{resource: %DB.Resource{id: id, title: title}}) do
    url = TransportWeb.Router.Helpers.resource_url(TransportWeb.Endpoint, :details, id) <> "#validation-report"

    "* #{title} - #{url}"
  end
end
