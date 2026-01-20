defmodule Transport.Jobs.ExpirationNotificationJob do
  @moduledoc """
  This job handles all expiration notifications for GTFS datasets:

  - **Admins**: Receives a single aggregated email with all expiring datasets
  - **Producers**: Receive individual emails per dataset they own
  - **Reusers**: Receive a daily digest of their favorited datasets

  ## Architecture

  The job uses a dispatcher pattern with two `perform/1` methods:

  1. **Dispatcher** (`perform(%{})`) - Triggered daily by cron:
     - Sends admin notification (aggregated email)
     - Sends producer notifications (per dataset)
     - Dispatches sub-jobs for reuser digests

  2. **Reuser digest worker** (`perform(%{"type" => "reuser_digest", ...})`):
     - Builds and sends personalized digest for a specific contact

  ## Notification delays

  - Producers/Admins: #{inspect(Transport.Expiration.producer_admin_delays())} days
  - Reusers: #{inspect(Transport.Expiration.reuser_delays())} days
  """
  use Oban.Worker,
    max_attempts: 3,
    tags: ["notifications"],
    # Prevents sending duplicate reuser digests.
    # The reuser_digest perform/1 uses (type + contact_id + digest_date) as args.
    unique: [period: {20, :hours}, fields: [:args, :queue, :worker]]

  import Ecto.Query
  alias Transport.Expiration

  @type delay() :: integer()
  @type dataset_ids() :: [integer()]
  @type datasets() :: [DB.Dataset.t()]
  @type delay_and_records() :: {delay(), [{DB.Dataset.t(), [DB.Resource.t()]}]}

  @notification_reason Transport.NotificationReason.reason(:expiration)

  # ============================================================================
  # Reuser digest worker
  # ============================================================================

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{"type" => "reuser_digest", "contact_id" => contact_id, "digest_date" => digest_date}
      }) do
    contact = DB.Repo.get!(DB.Contact, contact_id)
    subscribed_dataset_ids = subscribed_dataset_ids_for_expiration(contact)

    filtered_expiration_data =
      digest_date
      |> Date.from_iso8601!()
      |> gtfs_expiring_on_target_dates()
      |> Map.new(fn {delay, dataset_ids} ->
        ids = Enum.filter(dataset_ids, &(&1 in subscribed_dataset_ids))
        datasets = DB.Dataset.base_query() |> where([dataset: d], d.id in ^ids) |> DB.Repo.all()
        {delay, datasets}
      end)
      |> Map.reject(fn {_delay, datasets} -> Enum.empty?(datasets) end)

    send_reuser_email(contact, reuser_email_body(filtered_expiration_data))
    save_reuser_notifications(contact, filtered_expiration_data, job_id)

    :ok
  end

  # ============================================================================
  # Main dispatcher (triggered daily by cron)
  # ============================================================================

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args, inserted_at: %DateTime{} = inserted_at})
      when args in [%{}, nil] do
    target_date = DateTime.to_date(inserted_at)

    # 1. Send admin and producer notifications
    send_admin_and_producer_notifications(job_id)

    # 2. Dispatch reuser digest jobs
    dispatch_reuser_digest_jobs(target_date)

    :ok
  end

  # ============================================================================
  # Admin and Producer notifications
  # ============================================================================

  defp send_admin_and_producer_notifications(job_id) do
    expiration_data = compute_producer_admin_expiration_data()

    expiration_data
    |> send_admin_mail()
    |> Enum.each(&send_producer_notifications(&1, job_id))
  end

  @spec compute_producer_admin_expiration_data() :: [delay_and_records()]
  defp compute_producer_admin_expiration_data do
    for delay <- Expiration.producer_admin_delays(),
        date = Date.add(Date.utc_today(), delay) do
      {delay, Expiration.datasets_with_resources_expiring_on(date)}
    end
    |> Enum.reject(fn {_, records} -> Enum.empty?(records) end)
  end

  @spec send_admin_mail([delay_and_records()]) :: [delay_and_records()]
  defp send_admin_mail([] = records), do: records

  defp send_admin_mail(records) do
    Transport.AdminNotifier.expiration(records)
    |> Transport.Mailer.deliver()

    records
  end

  @spec send_producer_notifications(delay_and_records(), integer()) :: :ok
  defp send_producer_notifications({delay, records}, job_id) do
    Enum.each(records, fn {%DB.Dataset{} = dataset, resources} ->
      @notification_reason
      |> DB.NotificationSubscription.subscriptions_for_reason_dataset_and_role(dataset, :producer)
      |> Enum.each(fn %DB.NotificationSubscription{contact: %DB.Contact{} = contact} = subscription ->
        contact
        |> Transport.UserNotifier.expiration_producer(dataset, resources, delay)
        |> Transport.Mailer.deliver()

        DB.Notification.insert!(dataset, subscription, %{delay: delay, job_id: job_id})
      end)
    end)
  end

  # ============================================================================
  # Reuser digest dispatching
  # ============================================================================

  defp dispatch_reuser_digest_jobs(%Date{} = target_date) do
    expiring_gtfs_datasets_data = gtfs_expiring_on_target_dates(target_date)
    dataset_ids = expiring_gtfs_datasets_data |> Map.values() |> List.flatten()

    DB.Repo.transaction(
      fn ->
        dataset_ids
        |> contact_ids_subscribed_to_dataset_ids()
        |> Stream.chunk_every(100)
        |> Stream.each(fn contact_ids -> insert_reuser_digest_jobs(contact_ids, target_date) end)
        |> Stream.run()
      end,
      timeout: :timer.seconds(60)
    )
  end

  defp insert_reuser_digest_jobs(contact_ids, %Date{} = target_date) do
    # Oban caveat: can't use insert_all/2:
    # > Only the Smart Engine in Oban Pro supports bulk unique jobs and automatic batching.
    # > With the basic engine, you must use insert/3 for unique support.
    Enum.each(contact_ids, fn contact_id ->
      %{"type" => "reuser_digest", "contact_id" => contact_id, "digest_date" => target_date}
      |> new()
      |> Oban.insert()
    end)
  end

  # ============================================================================
  # Reuser email helpers
  # ============================================================================

  defp send_reuser_email(%DB.Contact{} = contact, html) do
    {:ok, _} = Transport.UserNotifier.expiration_reuser(contact, html) |> Transport.Mailer.deliver()
  end

  @spec save_reuser_notifications(DB.Contact.t(), %{delay() => datasets()}, integer()) :: :ok
  defp save_reuser_notifications(%DB.Contact{} = contact, delays_and_datasets, job_id) do
    delays_and_datasets
    |> Map.values()
    |> List.flatten()
    |> Enum.each(fn %DB.Dataset{} = dataset ->
      subscription =
        DB.Repo.get_by!(DB.NotificationSubscription,
          contact_id: contact.id,
          dataset_id: dataset.id,
          reason: @notification_reason,
          role: :reuser
        )

      DB.Notification.insert!(dataset, %{subscription | contact: contact}, %{job_id: job_id})
    end)
  end

  @spec reuser_email_body(%{delay() => datasets()}) :: binary()
  defp reuser_email_body(records) do
    records
    |> Enum.map_join("<br/>", &datasets_body/1)
    |> String.replace("\n", "")
  end

  @spec datasets_body({delay(), datasets()}) :: binary()
  defp datasets_body({delay, datasets}) do
    """
    <strong>Jeux de données #{Expiration.delay_str(delay)} :</strong>
    <ul>
    #{Enum.map_join(datasets, "<br/>", &dataset_link/1)}
    </ul>
    """
  end

  defp dataset_link(%DB.Dataset{slug: slug, custom_title: custom_title}) do
    url = TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, slug)
    ~s|<li><a href="#{url}">#{custom_title}</a></li>|
  end

  # ============================================================================
  # Subscription queries
  # ============================================================================

  defp subscribed_dataset_ids_for_expiration(%DB.Contact{id: contact_id}) do
    DB.NotificationSubscription.base_query()
    |> where(
      [notification_subscription: ns],
      ns.contact_id == ^contact_id and ns.role == :reuser and ns.reason == ^@notification_reason
    )
    |> select([notification_subscription: ns], ns.dataset_id)
    |> DB.Repo.all()
  end

  def contact_ids_subscribed_to_dataset_ids(dataset_ids) do
    DB.NotificationSubscription.base_query()
    |> where(
      [notification_subscription: ns],
      ns.reason == ^@notification_reason and ns.role == :reuser and ns.dataset_id in ^dataset_ids
    )
    |> select([notification_subscription: ns], ns.contact_id)
    |> DB.Repo.stream()
  end

  # ============================================================================
  # Dataset expiration queries (cached for reuser digests)
  # ============================================================================

  @doc """
  Identify datasets expiring on specific dates for reuser notifications.
  Uses a cache since this data is needed across multiple async jobs.
  """
  @spec gtfs_expiring_on_target_dates(Date.t()) :: %{delay() => dataset_ids()}
  def gtfs_expiring_on_target_dates(%Date{} = reference_date) do
    Transport.Cache.fetch(
      to_string(__MODULE__) <> ":gtfs_expiring_on_target_dates:#{reference_date}",
      fn -> Expiration.datasets_expiring_by_delay(reference_date, Expiration.reuser_delays()) end,
      :timer.minutes(10)
    )
  end
end
