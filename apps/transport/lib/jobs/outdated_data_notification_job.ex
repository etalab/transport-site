defmodule Transport.Jobs.OutdatedDataNotificationJob do
  @moduledoc """
  This module is in charge of sending notifications to both admins and users when data is outdated.
  """

  use Oban.Worker, max_attempts: 3, tags: ["notifications"]
  import Ecto.Query

  @type delay_and_records :: {integer(), [{DB.Dataset.t(), [DB.Resource.t()]}]}
  @expiration_reason Transport.NotificationReason.reason(:expiration)
  # If delay < 0, the resource is already expired
  @default_outdated_data_delays [-90, -60, -30, -45, -15, -7, -3, 0, 7, 14]

  @impl Oban.Worker

  def perform(%Oban.Job{id: job_id}) do
    outdated_data(job_id)
    :ok
  end

  def outdated_data(job_id) do
    for delay <- possible_delays(),
        date = Date.add(Date.utc_today(), delay) do
      {delay, gtfs_datasets_expiring_on(date)}
    end
    |> Enum.reject(fn {_, records} -> Enum.empty?(records) end)
    |> send_outdated_data_admin_mail()
    |> Enum.map(&send_outdated_data_producer_notifications(&1, job_id))
  end

  @spec gtfs_datasets_expiring_on(Date.t()) :: [{DB.Dataset.t(), [DB.Resource.t()]}]
  def gtfs_datasets_expiring_on(%Date{} = date) do
    DB.Dataset.base_query()
    |> DB.Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
    |> where(
      [metadata: m, resource: r],
      fragment("TO_DATE(?->>'end_date', 'YYYY-MM-DD')", m.metadata) == ^date and r.format == "GTFS"
    )
    |> select([dataset: d, resource: r], {d, r})
    |> distinct(true)
    |> DB.Repo.all()
    |> Enum.group_by(fn {%DB.Dataset{} = d, _} -> d end, fn {_, %DB.Resource{} = r} -> r end)
    |> Enum.to_list()
  end

  def possible_delays do
    @default_outdated_data_delays
    |> Enum.uniq()
    |> Enum.sort()
  end

  # A different email is sent to producers for every delay, containing all datasets expiring on this given delay
  @spec send_outdated_data_producer_notifications(delay_and_records(), integer()) :: :ok
  def send_outdated_data_producer_notifications({delay, records}, job_id) do
    Enum.each(records, fn {%DB.Dataset{} = dataset, resources} ->
      @expiration_reason
      |> DB.NotificationSubscription.subscriptions_for_reason_dataset_and_role(dataset, :producer)
      |> Enum.each(fn %DB.NotificationSubscription{contact: %DB.Contact{} = contact} = subscription ->
        contact
        |> Transport.UserNotifier.expiration_producer(dataset, resources, delay)
        |> Transport.Mailer.deliver()

        DB.Notification.insert!(dataset, subscription, %{delay: delay, job_id: job_id})
      end)
    end)
  end

  @spec send_outdated_data_admin_mail([delay_and_records()]) :: [delay_and_records()]
  defp send_outdated_data_admin_mail([] = _records), do: []

  defp send_outdated_data_admin_mail(records) do
    Transport.AdminNotifier.expiration(records)
    |> Transport.Mailer.deliver()

    records
  end
end
