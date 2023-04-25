defmodule Transport.Jobs.DatasetsSwitchingLicencesJob do
  @moduledoc """
  Job in charge of sending email notifications on a weekly basis to known
  - when datasets switch to the "licence ouverte" licence
  - were available under the the "licence ouverte" licence previously but switched licence
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]
  import Ecto.Query
  @notification_reason :datasets_switching_licences

  @impl Oban.Worker
  def perform(%Oban.Job{inserted_at: %DateTime{} = inserted_at}) do
    changes = inserted_at |> DateTime.to_date() |> Date.add(-1) |> datasets_licence_changes()

    datasets_previously_lo = datasets_previously_licence_ouverte(changes)
    datasets_now_lo = datasets_now_licence_ouverte(changes)

    send_email(datasets_previously_lo, datasets_now_lo)
  end

  def send_email([], []), do: :ok

  def send_email(datasets_previously_lo, datasets_now_lo) do
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
        "Suivi des jeux de données en licence ouverte",
        """
        Bonjour,

        #{now_licence_ouverte_txt(datasets_now_lo)}
        #{previously_licence_ouverte_txt(datasets_previously_lo)}

        L’équipe transport.data.gouv.fr

        ---
        Si vous souhaitez modifier ou supprimer ces alertes, vous pouvez répondre à cet e-mail.
        """,
        ""
      )
    end)

    save_notifications(datasets_previously_lo ++ datasets_now_lo, emails)

    :ok
  end

  def save_notifications(result, emails) do
    Enum.each(result, fn [%DB.DatasetHistory{}, %DB.Dataset{} = dataset, %DB.DatasetHistory{}] ->
      Enum.each(emails, fn email -> DB.Notification.insert!(@notification_reason, dataset, email) end)
    end)
  end

  defp dataset_link([%DB.DatasetHistory{}, %DB.Dataset{} = dataset, %DB.DatasetHistory{}]) do
    link = TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, dataset.slug)
    "* #{dataset.custom_title} - (#{DB.Dataset.type_to_str(dataset.type)}) - #{link}"
  end

  def now_licence_ouverte_txt([]), do: ""

  def now_licence_ouverte_txt(data) do
    """
    Les jeux de données suivants sont désormais publiés en licence ouverte :
    #{Enum.map_join(data, "\n", &dataset_link/1)}

    """
  end

  def previously_licence_ouverte_txt([]), do: ""

  def previously_licence_ouverte_txt(data) do
    """
    Les jeux de données suivants étaient publiés en licence ouverte et ont changé de licence :
    #{Enum.map_join(data, "\n", &dataset_link/1)}

    """
  end

  def datasets_previously_licence_ouverte(result) do
    Enum.filter(result, fn [%DB.DatasetHistory{} = recent_dh, %DB.Dataset{}, %DB.DatasetHistory{} = previous_dh] ->
      dataset_history_is_licence_ouverte?(previous_dh) and not dataset_history_is_licence_ouverte?(recent_dh)
    end)
  end

  def datasets_now_licence_ouverte(result) do
    Enum.filter(result, fn [%DB.DatasetHistory{} = recent_dh, %DB.Dataset{}, %DB.DatasetHistory{} = previous_dh] ->
      not dataset_history_is_licence_ouverte?(previous_dh) and dataset_history_is_licence_ouverte?(recent_dh)
    end)
  end

  @doc """
  Determines if a `DB.DatasetHistory` has a "licence ouverte" licence.

  iex> dataset_history_is_licence_ouverte?(%DB.DatasetHistory{payload: %{"licence" => "fr-lo"}})
  true
  iex> dataset_history_is_licence_ouverte?(%DB.DatasetHistory{payload: %{"licence" => "odc-odbl"}})
  false
  """
  def dataset_history_is_licence_ouverte?(%DB.DatasetHistory{payload: %{"licence" => licence}}) do
    DB.Dataset.has_licence_ouverte?(%DB.Dataset{licence: licence})
  end

  def datasets_licence_changes(%Date{} = date) do
    DB.DatasetHistory
    |> join(:inner, [dh], d in DB.Dataset, on: d.id == dh.dataset_id)
    # Join on the same table, same dataset, but compare to a week ago
    |> join(:inner, [dh, _d], dh2 in DB.DatasetHistory,
      on: dh2.dataset_id == dh.dataset_id and fragment("?::date = ?::date -7", dh2.inserted_at, dh.inserted_at)
    )
    |> where(
      [dh, _d, dh2],
      fragment("?::date = ? and ?->>'licence' != ?->>'licence'", dh.inserted_at, ^date, dh.payload, dh2.payload)
    )
    |> order_by([_dh, d, _dh2], asc: d.id)
    |> select([dh, d, dh2], [dh, d, dh2])
    |> DB.Repo.all()
  end
end
