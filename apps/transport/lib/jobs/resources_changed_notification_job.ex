defmodule Transport.Jobs.ResourcesChangedNotificationJob do
  @moduledoc """
  Job in charge of detecting datasets for which resources changed:
  - a resource has been added
  - a resource has been deleted
  - a download URL changed
  and notifying subscribers about this.
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]
  import Ecto.Query
  @notification_reason Transport.NotificationReason.reason(:resources_changed)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) when is_nil(args) or args == %{} do
    relevant_datasets()
    |> Enum.map(&new/1)
    |> Oban.insert_all()

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"dataset_id" => dataset_id}}) do
    dataset = DB.Dataset |> DB.Repo.get!(dataset_id)
    subject = "#{dataset.custom_title} : ressources modifiées"

    DB.NotificationSubscription.subscriptions_for_reason_dataset_and_role(@notification_reason, dataset, :reuser)
    |> Enum.each(fn %DB.NotificationSubscription{contact: %DB.Contact{} = contact} = subscription ->
      Transport.UserNotifier.resources_changed(contact, subject, dataset)
      |> Transport.Mailer.deliver()

      DB.Notification.insert!(dataset, subscription, %{job_id: job_id})
    end)
  end

  def relevant_datasets do
    today = Date.utc_today()

    # Latest `dataset_history` by dataset by day
    # (usually 1 row per day but make sure duplicates are handled)
    history_by_day_sub =
      DB.DatasetHistory
      |> select([d], max(d.id))
      |> group_by([d], [d.dataset_id, fragment("?::date", d.inserted_at)])

    urls_by_day_sub =
      DB.DatasetHistory
      |> join(:inner, [dh], dhr in DB.DatasetHistoryResources, on: dh.id == dhr.dataset_history_id)
      |> join(:inner, [_dh, dhr], r in DB.Resource, on: r.id == dhr.resource_id and not r.is_community_resource)
      |> where([dh, _dhr, _r], dh.id in subquery(history_by_day_sub))
      |> group_by([dh, _dhr, _r], [dh.dataset_id, fragment("?::date", dh.inserted_at)])
      |> select([dh, dhr, _d], %{
        dataset_id: dh.dataset_id,
        date: fragment("?::date", dh.inserted_at),
        urls: fragment("string_agg(?->>'download_url', ',' order by ?->>'download_url')", dhr.payload, dhr.payload)
      })

    base = from(today in subquery(urls_by_day_sub))

    base
    |> join(:inner, [today], yesterday in subquery(urls_by_day_sub),
      on:
        today.dataset_id == yesterday.dataset_id and
          yesterday.date == fragment("? - 1", today.date) and
          today.urls != yesterday.urls
    )
    |> where([today, _yesterday], today.date == ^today)
    |> DB.Repo.all()
  end
end
