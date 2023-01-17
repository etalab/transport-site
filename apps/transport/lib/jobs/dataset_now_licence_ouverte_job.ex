defmodule Transport.Jobs.DatasetNowLicenceOuverteJob do
  @moduledoc """
  Job in charge of sending notifications when the dataset switches to the "licence ouverte".
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]

  @notification_reason :dataset_now_licence_ouverte

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"dataset_id" => dataset_id}}) do
    dataset = DB.Repo.get!(DB.Dataset, dataset_id)

    dataset_link_fn = fn %DB.Dataset{} = dataset ->
      "* #{dataset.custom_title} - (#{DB.Dataset.type_to_str(dataset.type)}) - #{link(dataset)}"
    end

    Transport.Notifications.config()
    |> Transport.Notifications.emails_for_reason(@notification_reason)
    |> Enum.each(fn email ->
      Transport.EmailSender.impl().send_mail(
        "transport.data.gouv.fr",
        Application.get_env(:transport, :contact_email),
        email,
        Application.get_env(:transport, :contact_email),
        "Jeu de données maintenant en licence ouverte",
        """
        Bonjour,

        Le jeu de données suivant est désormais disponible en licence ouverte :

        #{dataset_link_fn.(dataset)}

        L’équipe transport.data.gouv.fr

        ---
        Si vous souhaitez modifier ou supprimer ces alertes, vous pouvez répondre à cet e-mail.
        """,
        ""
      )

      save_notification(dataset, email)
    end)

    :ok
  end

  def save_notification(%DB.Dataset{id: dataset_id}, email) do
    %DB.Notification{}
    |> DB.Notification.changeset(%{email: email, dataset_id: dataset_id, reason: @notification_reason})
    |> DB.Repo.insert!()
  end

  defp link(%DB.Dataset{slug: slug}), do: TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, slug)
end
