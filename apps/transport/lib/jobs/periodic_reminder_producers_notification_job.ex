defmodule Transport.Jobs.PeriodicReminderProducersNotificationJob do
  @moduledoc """
  A comment will be written later.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  @max_emails_per_day 100
  @notification_reason :periodic_reminder_producers

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, inserted_at: %DateTime{} = inserted_at}) when args == %{} or is_nil(args) do
    date = DateTime.to_date(inserted_at)

    if date == first_monday_of_month(date) do
      relevant_contacts() |> schedule_jobs(inserted_at)
    else
      {:discard, "Not the first Monday of the month"}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"contact_id" => contact_id}}) do
    contact =
      DB.Contact.base_query()
      |> preload([:organizations, notification_subscriptions: [:dataset]])
      |> DB.Repo.get!(contact_id)

    if contact |> subscribed_as_producer?() do
      send_mail_producer_with_subscriptions(contact)
    end

    :ok
  end

  defp send_mail_producer_with_subscriptions(%DB.Contact{notification_subscriptions: subscriptions} = contact) do
    other_producers_subscribers = contact |> other_producers_subscribers()

    Transport.EmailSender.impl().send_mail(
      "transport.data.gouv.fr",
      Application.get_env(:transport, :contact_email),
      contact.email,
      Application.get_env(:transport, :contact_email),
      "Rappel : vos notifications pour vos données sur transport.data.gouv.fr",
      "",
      Phoenix.View.render_to_string(TransportWeb.EmailView, "producer_with_subscriptions.html", %{
        datasets_subscribed:
          subscriptions
          |> Enum.filter(&(&1.role == :producer))
          |> Enum.map(& &1.dataset)
          |> Enum.uniq()
          |> Enum.sort_by(& &1.custom_title),
        has_other_producers_subscribers: not Enum.empty?(other_producers_subscribers),
        other_producers_subscribers: Enum.map_join(other_producers_subscribers, ", ", &DB.Contact.display_name/1)
      })
    )

    DB.Notification.insert!(@notification_reason, contact.email)
  end

  def contacts_in_orgs(org_ids) do
    DB.Organization
    |> preload(:contacts)
    |> where([o], o.id in ^org_ids)
    |> DB.Repo.all()
    |> Enum.flat_map(& &1.contacts)
    |> Enum.uniq()
    |> Enum.sort_by(&DB.Contact.display_name/1)
  end

  def all_orgs(%DB.Contact{organizations: orgs, notification_subscriptions: subscriptions}) do
    orgs
    |> Enum.map(& &1.id)
    |> Enum.concat(subscriptions |> Enum.map(& &1.dataset.organization_id))
    |> Enum.uniq()
  end

  def subscribed_as_producer?(%DB.Contact{notification_subscriptions: subscriptions}) do
    Enum.any?(subscriptions, &match?(%DB.NotificationSubscription{role: :producer}, &1))
  end

  def other_producers_subscribers(%DB.Contact{id: contact_id, notification_subscriptions: subscriptions}) do
    dataset_ids = subscriptions |> Enum.map(& &1.dataset_id) |> Enum.uniq()

    DB.NotificationSubscription.base_query()
    |> preload(:contact)
    |> where(
      [notification_subscription: ns],
      ns.contact_id != ^contact_id and ns.role == :producer and ns.dataset_id in ^dataset_ids
    )
    |> DB.Repo.all()
    |> Enum.map(& &1.contact)
    |> Enum.uniq()
    |> Enum.sort_by(&DB.Contact.display_name/1)
  end

  defp relevant_contacts do
    orgs_with_dataset =
      DB.Dataset.base_query()
      |> select([dataset: d], d.organization_id)
      |> distinct(true)
      |> DB.Repo.all()
      |> MapSet.new()

    # Identify contacts we want to reach:
    # - they have at least a subscription as a producer (=> review settings)
    # - they don't have subscriptions but they are a member of an org
    #   with published datasets (=> advertise subscriptions)
    DB.Contact.base_query()
    |> preload([:organizations, :notification_subscriptions])
    |> join(:left, [contact: c], c in assoc(c, :organizations), as: :organization)
    |> order_by([organization: o], asc: o.id)
    |> DB.Repo.all()
    |> Enum.filter(fn %DB.Contact{organizations: orgs} = contact ->
      org_has_published_dataset? = not MapSet.disjoint?(MapSet.new(orgs, & &1.id), orgs_with_dataset)

      subscribed_as_producer?(contact) or org_has_published_dataset?
    end)
  end

  defp schedule_jobs(contacts, %DateTime{} = scheduled_at) do
    contacts
    |> Enum.map(fn %DB.Contact{id: id} -> id end)
    |> Enum.chunk_every(chunk_size())
    # credo:disable-for-next-line Credo.Check.Warning.UnusedEnumOperation
    |> Enum.reduce(scheduled_at, fn ids, %DateTime{} = scheduled_at ->
      ids
      |> Enum.map(&(%{"contact_id" => &1} |> new(scheduled_at: scheduled_at)))
      |> Oban.insert_all()

      next_weekday(scheduled_at)
    end)

    :ok
  end

  @doc """
  How many e-mails are we going to send per day?
  Our daily free limit quota is set at 200 per day so we don't want to go over that.
  We set the chunk size to 1 in the test env to test the scheduling logic.
  """
  def chunk_size do
    case Mix.env() do
      :test -> 1
      _ -> @max_emails_per_day
    end
  end

  @doc """
  iex> first_monday_of_month(~D[2023-07-10])
  ~D[2023-07-03]
  iex> first_monday_of_month(~D[2023-08-07])
  ~D[2023-08-07]
  iex> first_monday_of_month(~D[2023-10-16])
  ~D[2023-10-02]
  iex> first_monday_of_month(~D[2024-01-08])
  ~D[2024-01-01]
  """
  def first_monday_of_month(%Date{} = date) do
    date
    |> Date.beginning_of_month()
    |> Date.add(6)
    |> Date.beginning_of_week(:monday)
  end

  @doc """
  iex> next_weekday(~U[2023-07-28 09:05:00Z])
  ~U[2023-07-31 09:05:00Z]
  iex> next_weekday(~U[2023-07-29 09:05:00Z])
  ~U[2023-07-31 09:05:00Z]
  iex> next_weekday(~U[2023-07-30 09:05:00Z])
  ~U[2023-07-31 09:05:00Z]
  iex> next_weekday(~U[2023-07-31 09:05:00Z])
  ~U[2023-08-01 09:05:00Z]
  iex> next_weekday(~U[2023-08-01 09:05:00Z])
  ~U[2023-08-02 09:05:00Z]
  """
  def next_weekday(%DateTime{} = datetime) do
    datetime = datetime |> DateTime.add(1, :day)

    if (datetime |> DateTime.to_date() |> Date.day_of_week()) in [6, 7] do
      next_weekday(datetime)
    else
      datetime
    end
  end
end
