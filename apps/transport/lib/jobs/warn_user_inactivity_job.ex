defmodule Transport.Jobs.WarnUserInactivityJob do
  @moduledoc """
  Sends an email to user that didn't log in for a while to warn them we will later prune their account.

  Later prune accounts that didn't take the chance.
  """
  use Oban.Worker
  @notification_reason Transport.NotificationReason.reason(:warn_user_inactivity)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{}}) do
    now = DateTime.utc_now()

    DB.Contact.delete_inactive_contacts(pruning_threshold(now))

    DB.Contact.list_inactive_contacts(inactivity_threshold(now))
    |> Enum.each(&warn_inactive_contact(pruning_threshold(now), &1))

    :ok
  end

  defp inactivity_threshold(now), do: DateTime.add(now, -30 * 24, :day)
  defp pruning_threshold(now), do: DateTime.add(now, -30 * 25, :day)

  defp warn_inactive_contact(%DateTime{} = pruning_dt, %DB.Contact{} = contact) do
    days_until_pruning =
      Date.diff(
        DateTime.to_date(contact.last_login_at),
        DateTime.to_date(pruning_dt)
      )

    if days_until_pruning in horizon_days() do
      actually_warn_inactive_contact(contact, days_until_pruning)
    end
  end

  defp actually_warn_inactive_contact(%DB.Contact{} = contact, horizon) do
    {:ok, _} = Transport.UserNotifier.warn_inactivity(contact, horizon_txt(horizon)) |> Transport.Mailer.deliver()
    save_notification(contact, horizon)
  end

  def horizon_days, do: [30, 15, 1]

  @doc """
  iex> Enum.each(Transport.Jobs.WarnUserInactivityJob.horizon_days(), &horizon_txt/1)
  :ok
  """
  def horizon_txt(horizon) do
    Map.fetch!(%{30 => "Dans 1 mois", 15 => "Dans 2 semaines", 1 => "Demain"}, horizon)
  end

  defp save_notification(%DB.Contact{} = contact, horizon) do
    DB.Notification.insert!(%{
      reason: @notification_reason,
      role: role(contact),
      contact_id: contact.id,
      email: contact.email,
      payload: %{"horizon" => horizon}
    })
  end

  defp role(%DB.Contact{} = contact) do
    contact = contact |> DB.Repo.preload(:organizations)

    if TransportWeb.Session.producer?(contact) do
      :producer
    else
      :reuser
    end
  end
end
