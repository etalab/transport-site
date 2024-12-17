defmodule Transport.Jobs.NewDatasetNotificationsJob do
  @moduledoc """
  Job in charge of sending notifications about datasets that have been added recently.
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]
  import Ecto.Query
  @new_dataset_reason Transport.NotificationReason.reason(:new_dataset)

  @impl Oban.Worker

  def perform(%Oban.Job{id: job_id, inserted_at: %DateTime{} = inserted_at}) do
    inserted_at |> relevant_datasets() |> send_new_dataset_notifications(job_id)
    :ok
  end

  def relevant_datasets(%DateTime{} = inserted_at) do
    datetime_limit = inserted_at |> DateTime.add(-1, :day)

    DB.Dataset.base_query()
    |> where([dataset: d], d.inserted_at >= ^datetime_limit)
    |> DB.Repo.all()
  end

  @spec send_new_dataset_notifications([DB.Dataset.t()] | [], pos_integer()) :: no_return() | :ok
  def send_new_dataset_notifications([], _job_id), do: :ok

  def send_new_dataset_notifications(datasets, job_id) do
    @new_dataset_reason
    |> DB.NotificationSubscription.subscriptions_for_reason_and_role(:reuser)
    |> Enum.each(fn %DB.NotificationSubscription{contact: %DB.Contact{} = contact} = subscription ->
      contact
      |> Transport.UserNotifier.new_datasets(datasets)
      |> Transport.Mailer.deliver()

      DB.Notification.insert!(subscription, %{dataset_ids: Enum.map(datasets, & &1.id), job_id: job_id})
    end)
  end
end
