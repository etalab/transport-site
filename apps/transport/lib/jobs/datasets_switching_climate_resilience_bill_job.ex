defmodule Transport.Jobs.DatasetsSwitchingClimateResilienceBillJob do
  @moduledoc """
  Job in charge of sending email notifications on a weekly basis to know:
  - when datasets are subject to a compulsory data integration obligation (article 122)
  - were previously subject to to a compulsory data integration obligation but are not any more
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]
  import Ecto.Query
  @notification_reason DB.NotificationSubscription.reason(:datasets_switching_climate_resilience_bill)

  @impl Oban.Worker
  def perform(%Oban.Job{inserted_at: %DateTime{} = inserted_at}) do
    changes = inserted_at |> DateTime.to_date() |> Date.add(-1) |> datasets_custom_tags_changes()

    datasets_previously_climate_resilience = datasets_previously_climate_resilience_bill(changes)
    datasets_now_climate_resilience = datasets_now_climate_resilience_bill(changes)

    send_email(datasets_previously_climate_resilience, datasets_now_climate_resilience)
  end

  def send_email([], []), do: :ok

  def send_email(datasets_previously_climate_resilience, datasets_now_climate_resilience) do
    emails =
      @notification_reason
      |> DB.NotificationSubscription.subscriptions_for_reason()
      |> DB.NotificationSubscription.subscriptions_to_emails()

    Enum.each(emails, fn email ->
      Transport.EmailSender.impl().send_mail(
        "transport.data.gouv.fr",
        Application.get_env(:transport, :contact_email),
        email,
        Application.get_env(:transport, :contact_email),
        "Loi climat et résilience : suivi des jeux de données",
        "",
        Phoenix.View.render_to_string(TransportWeb.EmailView, "datasets_switching_climate_resilience_bill.html", %{
          datasets_now_climate_resilience: Enum.map(datasets_now_climate_resilience, &Enum.at(&1, 1)),
          datasets_previously_climate_resilience: Enum.map(datasets_previously_climate_resilience, &Enum.at(&1, 1))
        })
      )
    end)

    save_notifications(datasets_previously_climate_resilience ++ datasets_now_climate_resilience, emails)

    :ok
  end

  def save_notifications(result, emails) do
    Enum.each(result, fn [%DB.DatasetHistory{}, %DB.Dataset{} = dataset, %DB.DatasetHistory{}] ->
      Enum.each(emails, fn email -> DB.Notification.insert!(@notification_reason, dataset, email) end)
    end)
  end

  def datasets_previously_climate_resilience_bill(result) do
    Enum.filter(result, fn [%DB.DatasetHistory{} = recent_dh, %DB.Dataset{}, %DB.DatasetHistory{} = previous_dh] ->
      has_climate_resilience_bill_tag?(previous_dh) and not has_climate_resilience_bill_tag?(recent_dh)
    end)
  end

  def datasets_now_climate_resilience_bill(result) do
    Enum.filter(result, fn [%DB.DatasetHistory{} = recent_dh, %DB.Dataset{}, %DB.DatasetHistory{} = previous_dh] ->
      not has_climate_resilience_bill_tag?(previous_dh) and has_climate_resilience_bill_tag?(recent_dh)
    end)
  end

  @doc """
  iex> has_climate_resilience_bill_tag?(%DB.DatasetHistory{payload: %{"custom_tags" => ["loi-climat-resilience"]}})
  true
  iex> has_climate_resilience_bill_tag?(%DB.DatasetHistory{payload: %{"custom_tags" => nil}})
  false
  iex> has_climate_resilience_bill_tag?(%DB.DatasetHistory{payload: %{"custom_tags" => ["foo"]}})
  false
  """
  def has_climate_resilience_bill_tag?(%DB.DatasetHistory{payload: %{"custom_tags" => custom_tags}}) do
    "loi-climat-resilience" in (custom_tags || [])
  end

  def datasets_custom_tags_changes(%Date{} = date) do
    DB.DatasetHistory
    |> join(:inner, [dh], d in DB.Dataset, on: d.id == dh.dataset_id)
    # Join on the same table, same dataset, but compare to a week ago
    |> join(:inner, [dh, _d], dh2 in DB.DatasetHistory,
      on: dh2.dataset_id == dh.dataset_id and fragment("?::date = ?::date -7", dh2.inserted_at, dh.inserted_at)
    )
    |> where(
      [dh, _d, dh2],
      fragment(
        "?::date = ? and coalesce(?->>'custom_tags', '[]') != coalesce(?->>'custom_tags', '[]')",
        dh.inserted_at,
        ^date,
        dh.payload,
        dh2.payload
      )
    )
    |> order_by([_dh, d, _dh2], asc: d.id)
    |> select([dh, d, dh2], [dh, d, dh2])
    |> DB.Repo.all()
  end
end
