defmodule Transport.DataChecker do
  @moduledoc """
  Use to check data for two things:
  - Toggle in and of active status of datasets depending on status on data.gouv.fr
  - Send notifications to producers and admins when data is outdated
  """
  alias DB.{Dataset, Repo}
  import Ecto.Query
  require Logger

  @type delay_and_records :: {integer(), [{DB.Dataset.t(), [DB.Resource.t()]}]}
  @type dataset_status :: :active | :inactive | :ignore | :no_producer | {:archived, DateTime.t()}
  @expiration_reason Transport.NotificationReason.reason(:expiration)
  @new_dataset_reason Transport.NotificationReason.reason(:new_dataset)
  # If delay < 0, the resource is already expired
  @default_outdated_data_delays [-90, -60, -30, -45, -15, -7, -3, 0, 7, 14]

  @doc """
  This method is a scheduled job which does two things:
  - locally re-activates disabled datasets which are actually active on data gouv
  - locally disables datasets which are actually inactive on data gouv

  It also sends an email to the team via `fmt_inactive_datasets` and `fmt_reactivated_datasets`.
  """
  def inactive_data do
    # Some datasets marked as inactive in our database may have reappeared
    # on the data gouv side, we'll mark them back as active.
    datasets_statuses = datasets_datagouv_statuses()

    to_reactivate_datasets = for {%Dataset{is_active: false} = dataset, :active} <- datasets_statuses, do: dataset

    reactivated_ids = Enum.map(to_reactivate_datasets, & &1.id)

    Dataset
    |> where([d], d.id in ^reactivated_ids)
    |> Repo.update_all(set: [is_active: true])

    # Some datasets marked as active in our database may have disappeared
    # on the data gouv side, mark them as inactive.
    current_nb_active_datasets = Repo.aggregate(Dataset.base_query(), :count, :id)

    inactive_datasets =
      for {%DB.Dataset{is_active: true} = dataset, status} <- datasets_statuses,
          status in [:inactive, :no_producer],
          do: dataset

    inactive_ids = Enum.map(inactive_datasets, & &1.id)
    desactivates_over_10_percent_datasets = Enum.count(inactive_datasets) > current_nb_active_datasets * 10 / 100

    if desactivates_over_10_percent_datasets do
      raise "Would desactivate over 10% of active datasets, stopping"
    end

    Dataset
    |> where([d], d.id in ^inactive_ids)
    |> Repo.update_all(set: [is_active: false])

    # Some datasets may be archived on data.gouv.fr
    recent_limit = DateTime.add(DateTime.utc_now(), -1, :day)

    archived_datasets =
      for {%Dataset{is_active: true} = dataset, {:archived, datetime}} <- datasets_statuses,
          DateTime.compare(datetime, recent_limit) == :gt,
          do: dataset

    send_inactive_datasets_mail(to_reactivate_datasets, inactive_datasets, archived_datasets)
  end

  @spec datasets_datagouv_statuses :: [{DB.Dataset.t(), dataset_status()}]
  def datasets_datagouv_statuses do
    DB.Dataset
    |> order_by(:id)
    |> DB.Repo.all()
    |> Enum.map(&{&1, dataset_status(&1)})
  end

  @spec dataset_status(DB.Dataset.t()) :: dataset_status()
  def dataset_status(%DB.Dataset{datagouv_id: datagouv_id}) do
    case Datagouvfr.Client.Datasets.get(datagouv_id) do
      {:ok, %{"organization" => nil, "owner" => nil}} ->
        :no_producer

      {:ok, %{"archived" => nil}} ->
        :active

      {:ok, %{"archived" => archived}} ->
        {:ok, datetime, 0} = DateTime.from_iso8601(archived)
        {:archived, datetime}

      {:error, %HTTPoison.Error{} = error} ->
        log_sentry_event(datagouv_id, error)
        :ignore

      {:error, reason} when reason in [:not_found, :gone] ->
        :inactive

      {:error, error} ->
        log_sentry_event(datagouv_id, error)
        :ignore
    end
  end

  defp log_sentry_event(datagouv_id, error) do
    Sentry.capture_message(
      "Unable to get dataset status for Dataset##{datagouv_id} from data.gouv.fr",
      fingerprint: ["#{__MODULE__}:dataset_status:error"],
      extra: %{dataset_datagouv_id: datagouv_id, error_reason: inspect(error)}
    )
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

  @spec send_new_dataset_notifications([Dataset.t()] | []) :: no_return() | :ok
  def send_new_dataset_notifications([]), do: :ok

  def send_new_dataset_notifications(datasets) do
    # Generated as an integer rather than a UUID because `payload.job_id`
    # for other notifications are %Oban.Job.id (bigint).
    job_id = Enum.random(1..Integer.pow(2, 63))

    @new_dataset_reason
    |> DB.NotificationSubscription.subscriptions_for_reason_and_role(:reuser)
    |> Enum.each(fn %DB.NotificationSubscription{contact: %DB.Contact{} = contact} = subscription ->
      contact
      |> Transport.UserNotifier.new_datasets(datasets)
      |> Transport.Mailer.deliver()

      DB.Notification.insert!(subscription, %{dataset_ids: Enum.map(datasets, & &1.id), job_id: job_id})
    end)
  end

  @spec send_outdated_data_producer_notifications(delay_and_records(), integer()) :: delay_and_records()
  def send_outdated_data_producer_notifications({delay, records} = payload, job_id) do
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

    payload
  end

  @doc """
  iex> resource_titles([%DB.Resource{title: "B"}])
  "B"
  iex> resource_titles([%DB.Resource{title: "B"}, %DB.Resource{title: "A"}])
  "A, B"
  """
  def resource_titles(resources) do
    resources
    |> Enum.sort_by(fn %DB.Resource{title: title} -> title end)
    |> Enum.map_join(", ", fn %DB.Resource{title: title} -> title end)
  end

  @spec send_outdated_data_admin_mail([delay_and_records()]) :: [delay_and_records()]
  defp send_outdated_data_admin_mail([] = _records), do: []

  defp send_outdated_data_admin_mail(records) do
    Transport.AdminNotifier.expiration(records)
    |> Transport.Mailer.deliver()

    records
  end

  # Do nothing if all lists are empty
  defp send_inactive_datasets_mail([] = _reactivated_datasets, [] = _inactive_datasets, [] = _archived_datasets),
    do: nil

  defp send_inactive_datasets_mail(reactivated_datasets, inactive_datasets, archived_datasets) do
    Transport.AdminNotifier.inactive_datasets(reactivated_datasets, inactive_datasets, archived_datasets)
    |> Transport.Mailer.deliver()
  end
end
