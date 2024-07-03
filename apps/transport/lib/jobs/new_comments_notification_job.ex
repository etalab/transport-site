defmodule Transport.Jobs.NewCommentsNotificationJob do
  @moduledoc """
  Job sending email notifications to each reuser when comments have been posted
  on datasets they follow.

  `dataset.latest_data_gouv_comment_timestamp` is updated daily by
  `Transport.CommentsChecker` and is currently in charge of sending
  notifications to producers.

  This job should be scheduled for every weekday.
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]
  import Ecto.Query
  @notification_reason Transport.NotificationReason.reason(:daily_new_comments)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"contact_id" => contact_id, "dataset_ids" => dataset_ids}}) do
    subscription =
      DB.NotificationSubscription
      |> DB.Repo.get_by!(reason: @notification_reason, contact_id: contact_id)
      |> DB.Repo.preload(:contact)

    contact = Map.fetch!(subscription, :contact)

    datasets =
      DB.Contact.base_query()
      |> join(:inner, [contact: c], d in assoc(c, :followed_datasets), as: :dataset)
      |> where([contact: c, dataset: d], c.id == ^contact_id and d.id in ^dataset_ids)
      |> select([dataset: d], d)
      |> DB.Repo.all()

    contact
    |> Transport.UserNotifier.new_comments_reuser(datasets)
    |> Transport.Mailer.deliver()

    DB.Notification.insert!(subscription, %{dataset_ids: Enum.map(datasets, & &1.id)})
    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{scheduled_at: %DateTime{} = scheduled_at}) do
    dataset_ids = scheduled_at |> relevant_datasets_query() |> select([dataset: d], d.id) |> DB.Repo.all()

    scheduled_at
    |> relevant_contacts()
    |> Enum.map(fn %DB.Contact{id: contact_id} -> new(%{contact_id: contact_id, dataset_ids: dataset_ids}) end)
    |> Oban.insert_all()

    :ok
  end

  @doc """
  Identifies contacts for which we should send an email today.
  - they follow datasets with recent comments
  - they are subscribed to the relevant notification's reason
  """
  def relevant_contacts(%DateTime{} = datetime) do
    datetime
    |> relevant_datasets_query()
    |> join(:inner, [dataset: d], f in assoc(d, :followers), as: :contact)
    |> join(:inner, [contact: c], ns in assoc(c, :notification_subscriptions), as: :notification_subscription)
    |> where([notification_subscription: ns], ns.role == :reuser and ns.reason == @notification_reason)
    |> select([contact: c], c)
    |> distinct(true)
    |> DB.Repo.all()
  end

  @doc """
  Identifies datasets for which new comments have been posted recently.
  [Tuesday; Thursday] -> last day
  Monday -> Friday, Saturday or Sunday
  """
  def relevant_datasets_query(%DateTime{} = datetime) do
    days_delay = datetime |> DateTime.to_date() |> nb_days_delay()
    dt_limit = DateTime.add(datetime, -days_delay, :day)

    DB.Dataset.base_query()
    |> where([dataset: d], not is_nil(d.latest_data_gouv_comment_timestamp))
    |> where([dataset: d], d.latest_data_gouv_comment_timestamp >= ^dt_limit)
  end

  @doc """
  iex> nb_days_delay(~D[2024-03-28])
  1
  iex> nb_days_delay(~D[2024-03-25])
  3
  """
  def nb_days_delay(%Date{} = date) do
    if Date.day_of_week(date) == 1, do: 3, else: 1
  end
end
