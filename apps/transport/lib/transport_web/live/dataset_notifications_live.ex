defmodule TransportWeb.Live.DatasetNotificationsLive do
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  use Gettext, backend: TransportWeb.Gettext
  alias TransportWeb.Live.NotificationsLive

  @role :reuser

  @impl true
  def mount(_params, %{"current_user" => %{"id" => user_id}, "locale" => locale, "dataset_id" => dataset_id}, socket) do
    Gettext.put_locale(locale)

    current_contact = DB.Repo.get_by!(DB.Contact, datagouv_user_id: user_id)
    dataset = DB.Repo.get!(DB.Dataset, dataset_id)

    socket =
      assign(socket, %{
        current_contact: current_contact,
        role: @role,
        datasets: [dataset],
        dataset: dataset,
        subscriptions: subscriptions(dataset, current_contact),
        available_reasons: NotificationsLive.available_reasons(@role)
      })

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle" = event_name, %{} = params, %Phoenix.LiveView.Socket{} = socket) do
    NotificationsLive.handle_event(event_name, params, socket)
  end

  defp subscriptions(%DB.Dataset{} = dataset, %DB.Contact{} = contact) do
    NotificationsLive.notification_subscriptions_for_datasets([dataset], contact, @role)
  end
end
