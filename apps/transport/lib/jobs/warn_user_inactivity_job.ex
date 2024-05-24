defmodule Transport.Jobs.WarnUserInactivityJob do
  @moduledoc """
  Sends an email to user that didn't log in for a while to warn them we will later prune their account.

  Later prune accounts that didn't take the chance.
  """
  use Oban.Worker

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

    case days_until_pruning do
      30 ->
        {:ok, _} =
          actually_warn_inactive_contact(contact.email, "Dans 1 mois")

      15 ->
        {:ok, _} =
          actually_warn_inactive_contact(contact.email, "Dans 2 semaines")

      1 ->
        {:ok, _} =
          actually_warn_inactive_contact(contact.email, "Demain")

      _ ->
        {}
    end
  end

  defp actually_warn_inactive_contact(email, horizon) do
    {:ok, _} = Transport.UserNotifier.warn_inactivity(email, horizon) |> Transport.Mailer.deliver()
  end
end
