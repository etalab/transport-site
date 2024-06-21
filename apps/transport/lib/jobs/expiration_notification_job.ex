defmodule Transport.Jobs.ExpirationNotificationJob do
  @moduledoc """
  This job sends daily digests to reusers about the expiration of their favorited datasets.
  The expiration delays is the same for all reusers and cannot be customized for now.

  It has 2 `perform/1` methods:
  - a dispatcher one in charge of identifying contacts we should get in touch with today
  - another in charge of building the daily digest for a specific contact (with only their favorited datasets)
  """
  use Oban.Worker,
    max_attempts: 3,
    tags: ["notifications"],
    # Make sure we don't send twice the daily digest to a contact.
    # The relevant `perform/1` uses (contact_id + digest_date) as args
    # to leverage the unique clause.
    unique: [period: {20, :hours}, fields: [:args, :queue, :worker]]

  @type delay() :: integer()
  @type dataset_ids() :: [integer()]
  @type datasets() :: [DB.Dataset.t()]

  import Ecto.Query
  @notification_reason DB.NotificationSubscription.reason(:expiration)
  # If delay < 0, the resource is already expired
  @default_outdated_data_delays [-30, -7, 0, 7, 14]

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"contact_id" => contact_id, "digest_date" => digest_date}}) do
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

    send_email(contact, email_body(filtered_expiration_data))
    save_notifications(contact, filtered_expiration_data, job_id)

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, inserted_at: %DateTime{} = inserted_at}) when args in [%{}, nil] do
    target_date = DateTime.to_date(inserted_at)
    expiring_gtfs_datasets_data = gtfs_expiring_on_target_dates(target_date)
    dataset_ids = expiring_gtfs_datasets_data |> Map.values() |> List.flatten()

    DB.Repo.transaction(
      fn ->
        dataset_ids
        |> contact_ids_subscribed_to_dataset_ids()
        |> Stream.chunk_every(100)
        |> Stream.each(fn contact_ids -> insert_jobs(contact_ids, target_date) end)
        |> Stream.run()
      end,
      timeout: :timer.seconds(60)
    )

    :ok
  end

  defp send_email(%DB.Contact{} = contact, html) do
    {:ok, _} = Transport.UserNotifier.expiration_reuser(contact, html) |> Transport.Mailer.deliver()
  end

  @spec save_notifications(DB.Contact.t(), %{delay() => datasets()}, integer()) :: :ok
  defp save_notifications(%DB.Contact{} = contact, delays_and_datasets, job_id) do
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

      DB.Notification.insert!(dataset, %DB.NotificationSubscription{subscription | contact: contact}, %{job_id: job_id})
    end)
  end

  defp subscribed_dataset_ids_for_expiration(%DB.Contact{id: contact_id}) do
    DB.NotificationSubscription.base_query()
    |> where(
      [notification_subscription: ns],
      ns.contact_id == ^contact_id and ns.role == :reuser and ns.reason == ^@notification_reason
    )
    |> select([notification_subscription: ns], ns.dataset_id)
    |> DB.Repo.all()
  end

  @spec email_body(%{delay() => datasets()}) :: binary()
  defp email_body(records) do
    records
    |> Enum.map_join("<br/>", &datasets_body/1)
    |> String.replace("\n", "")
  end

  @spec datasets_body({delay(), datasets()}) :: binary()
  defp datasets_body({delay, datasets}) do
    """
    <strong>Jeux de données #{delay_str(delay)} :</strong>
    <ul>
    #{Enum.map_join(datasets, "<br/>", &dataset_link/1)}
    </ul>
    """
  end

  defp dataset_link(%DB.Dataset{slug: slug, custom_title: custom_title}) do
    url = TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, slug)
    ~s|<li><a href="#{url}">#{custom_title}</a></li>|
  end

  @doc """
  iex> delay_str(0)
  "périmant demain"
  iex> delay_str(2)
  "périmant dans 2 jours"
  iex> delay_str(-1)
  "périmé depuis hier"
  iex> delay_str(-2)
  "périmés depuis 2 jours"
  """
  def delay_str(0), do: "périmant demain"
  def delay_str(1), do: "périmant dans 1 jour"
  def delay_str(d) when d >= 2, do: "périmant dans #{d} jours"
  def delay_str(-1), do: "périmé depuis hier"
  def delay_str(d) when d <= -2, do: "périmés depuis #{-d} jours"

  defp insert_jobs(contact_ids, %Date{} = target_date) do
    # Oban caveat: can't use [insert_all/2](https://hexdocs.pm/oban/Oban.html#insert_all/2):
    # > Only the Smart Engine in Oban Pro supports bulk unique jobs and automatic batching.
    # > With the basic engine, you must use insert/3 for unique support.
    Enum.each(contact_ids, fn contact_id ->
      %{"contact_id" => contact_id, "digest_date" => target_date}
      |> new()
      |> Oban.insert()
    end)
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

  @doc """
  Identify datasets expiring on specific dates.
  We only support GTFS resources at the moment.
  A dataset expires on a specific date if at least a resource expires on this date.

  Since this data is needed in asynchronous jobs, we use a cache to share
  it across jobs.
  """
  @spec gtfs_expiring_on_target_dates(Date.t()) :: %{delay() => dataset_ids()}
  def gtfs_expiring_on_target_dates(%Date{} = reference_date) do
    Transport.Cache.fetch(
      to_string(__MODULE__) <> ":gtfs_expiring_on_target_dates:#{reference_date}",
      fn ->
        delays_and_dates = delays_and_dates(reference_date)
        dates_and_delays = Map.new(delays_and_dates, fn {key, value} -> {value, key} end)
        expiring_dates = Map.values(delays_and_dates)

        DB.Dataset.base_query()
        |> DB.Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
        |> where([resource: r], r.format == "GTFS")
        |> where(
          [metadata: m],
          fragment("TO_DATE(?->>'end_date', 'YYYY-MM-DD')", m.metadata) in ^expiring_dates
        )
        |> select([dataset: d, metadata: m], %{
          dataset_id: d.id,
          end_date: fragment("TO_DATE(?->>'end_date', 'YYYY-MM-DD')", m.metadata)
        })
        |> distinct(true)
        |> DB.Repo.all()
        # Example output: a map with %{expiration_delay, [dataset_ids]}
        # `%{-7 => [468, 600], 0 => [656, 919, 790, 931]}`
        |> Enum.group_by(
          fn %{end_date: end_date} -> Map.fetch!(dates_and_delays, end_date) end,
          fn %{dataset_id: dataset_id} -> dataset_id end
        )
      end,
      :timer.minutes(10)
    )
  end

  @doc """
  iex> delays_and_dates(~D[2024-05-21])
  %{
    -30 => ~D[2024-04-21],
    -7 => ~D[2024-05-14],
    0 => ~D[2024-05-21],
    7 => ~D[2024-05-28],
    14 => ~D[2024-06-04]
  }
  """
  @spec delays_and_dates(Date.t()) :: %{delay() => Date.t()}
  def delays_and_dates(%Date{} = date) do
    Map.new(@default_outdated_data_delays, fn delay -> {delay, Date.add(date, delay)} end)
  end
end
