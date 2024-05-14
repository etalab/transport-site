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
    days_until_pruning = DateTime.diff(contact.last_login_at, pruning_dt, :day)

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
    Transport.WarnUserInactivityNotifier.warn_inactivity(email, horizon)
    |> Transport.Mailer.deliver()
  end
end

defmodule Transport.WarnUserInactivityNotifier do
  @moduledoc """
  Module in charge of building the emails.
  """
  use Phoenix.Swoosh, view: TransportWeb.EmailView

  def warn_inactivity(email, horizon) do
    new()
    |> from({"transport.data.gouv.fr", Application.fetch_env!(:transport, :contact_email)})
    |> reply_to(Application.fetch_env!(:transport, :contact_email))
    |> to(email)
    |> subject("Votre compte sera supprimé #{String.downcase(horizon)}")
    |> render_body("warn_inactivity.html", contact_email: email, horizon: horizon)
  end
end
