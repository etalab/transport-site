defmodule Transport.Jobs.DatasetNowOnNAPNotificationJob do
  @moduledoc """
  Job in charge of sending a welcome notification to producers when a dataset has been added on the NAP.
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"], unique: [period: :infinity]
  import Ecto.Query

  @notification_reason :dataset_now_on_nap

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"dataset_id" => dataset_id}, id: job_id}) do
    dataset = DB.Repo.get!(DB.Dataset, dataset_id)

    dataset
    |> DB.NotificationSubscription.subscriptions_for_dataset()
    |> DB.NotificationSubscription.subscriptions_to_emails()
    |> MapSet.new()
    |> MapSet.difference(email_addresses_already_sent(dataset))
    |> Enum.each(fn email ->
      Transport.EmailSender.impl().send_mail(
        "transport.data.gouv.fr",
        Application.get_env(:transport, :contact_email),
        email,
        Application.get_env(:transport, :contact_email),
        "Votre jeu de données a été référencé sur transport.data.gouv.fr",
        "",
        Phoenix.View.render_to_string(TransportWeb.EmailView, "dataset_now_on_nap.html",
          dataset_url: TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, dataset.slug),
          dataset_custom_title: dataset.custom_title,
          contact_email_address: Application.get_env(:transport, :contact_email)
        )
      )

      save_notification(dataset, email)
    end)

    Oban.Notifier.notify(Oban, :gossip, %{complete: job_id})
  end

  defp save_notification(%DB.Dataset{} = dataset, email) do
    DB.Notification.insert!(@notification_reason, dataset, email)
  end

  @spec email_addresses_already_sent(DB.Dataset.t()) :: MapSet.t()
  defp email_addresses_already_sent(%DB.Dataset{id: dataset_id}) do
    DB.Notification
    |> where([n], n.dataset_id == ^dataset_id and n.reason == @notification_reason)
    |> select([n], n.email)
    |> DB.Repo.all()
    |> MapSet.new()
  end
end
