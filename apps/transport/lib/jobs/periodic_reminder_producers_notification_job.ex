defmodule Transport.Jobs.PeriodicReminderProducersNotificationJob do
  @moduledoc """
  A comment will be written later.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  @max_emails_per_day 100

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
  def perform(%Oban.Job{args: %{"contact_id" => _contact_id}}) do
    :ok
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
    |> order_by([organization: o], desc: o.id)
    |> DB.Repo.all()
    |> Enum.filter(fn %DB.Contact{notification_subscriptions: subscriptions, organizations: orgs} ->
      subscribed_as_producer? = Enum.any?(subscriptions, &match?(%DB.NotificationSubscription{role: :producer}, &1))
      org_has_published_dataset? = not MapSet.disjoint?(MapSet.new(orgs, & &1.id), orgs_with_dataset)

      subscribed_as_producer? or org_has_published_dataset?
    end)
  end

  defp schedule_jobs(contacts, %DateTime{} = scheduled_at) do
    contacts
    |> Enum.map(fn %DB.Contact{id: id} -> id end)
    |> Enum.chunk_every(@max_emails_per_day)
    |> Enum.with_index(0)
    |> Enum.each(fn {ids, index} ->
      scheduled_at =
        case index do
          0 -> scheduled_at
          _ -> next_weekday(scheduled_at)
        end

      ids
      |> Enum.map(&(%{"contact_id" => &1} |> new(scheduled_at: scheduled_at)))
      |> Oban.insert_all()
    end)
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
