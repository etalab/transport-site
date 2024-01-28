defmodule TransportWeb.Backoffice.IRVEDashboardLive do
  use Phoenix.LiveView
  use Phoenix.HTML
  import TransportWeb.Backoffice.JobsLive, only: [ensure_admin_auth_or_redirect: 3]
  import TransportWeb.Router.Helpers

  @impl true
  def mount(_params, %{"current_user" => current_user} = _session, socket) do
    {:ok,
     ensure_admin_auth_or_redirect(socket, current_user, fn socket ->
       socket
       |> assign_data()
     end)}
  end

  def assign_data(socket) do
    socket
    |> assign(:processing_report, latest_report!())
  end

  import Ecto.Query, only: [from: 2, first: 1]

  def latest_report! do
    # TODO: sort by valid + nb pdc desc
    report =
      from(pr in DB.ProcessingReport, order_by: {:desc, :id}, limit: 1)
      |> first()
      |> DB.Repo.one()

    report.content
  end
end
