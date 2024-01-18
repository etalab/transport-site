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
    |> assign(:items, [])
  end
end
