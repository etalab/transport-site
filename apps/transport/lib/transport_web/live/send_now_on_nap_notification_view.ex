defmodule TransportWeb.Live.SendNowOnNAPNotificationView do
  use Phoenix.LiveView
  import TransportWeb.Gettext, only: [dgettext: 2]
  require Logger

  @button_disabled [:sending, :sent]

  def render(assigns) do
    ~H"""
    <button :if={@display_button} class={@button_class} phx-click="dispatch_job" disabled={@button_disabled}>
      <%= @button_text %>
    </button>
    """
  end

  def mount(_params, %{"dataset_id" => dataset_id, "locale" => locale, "sent_reasons" => sent_reasons}, socket) do
    Gettext.put_locale(locale)

    new_socket =
      socket
      |> assign(:display_button, display_button?(dataset_id, sent_reasons))
      |> assign(dataset_id: dataset_id)
      |> assign_step(:first)

    {:ok, new_socket}
  end

  defp display_button?(dataset_id, sent_reasons) do
    dataset = DB.Repo.get!(DB.Dataset, dataset_id)
    not_sent = Transport.NotificationReason.reason(:dataset_now_on_nap) not in sent_reasons
    recently_added?(dataset) and not_sent
  end

  defp recently_added?(%DB.Dataset{inserted_at: nil}), do: false

  defp recently_added?(%DB.Dataset{inserted_at: %DateTime{} = inserted_at}) do
    DateTime.diff(inserted_at, DateTime.utc_now(), :day) >= -30
  end

  def handle_event("dispatch_job", _value, socket) do
    send(self(), {:dispatch, socket.assigns.dataset_id})
    {:noreply, socket}
  end

  def handle_info({:dispatch, dataset_id}, socket) do
    new_socket =
      case %{dataset_id: dataset_id} |> Transport.Jobs.DatasetNowOnNAPNotificationJob.new() |> Oban.insert() do
        {:ok, %Oban.Job{id: job_id}} ->
          send(self(), {:wait_for_completion, job_id})
          assign_step(socket, :sending)
      end

    {:noreply, new_socket}
  end

  def handle_info({:wait_for_completion, job_id}, socket) do
    :ok = Oban.Notifier.listen([:gossip])

    new_socket =
      receive do
        {:notification, :gossip, %{"complete" => ^job_id}} ->
          socket |> assign_step(:sent)
      end

    Oban.Notifier.unlisten([:gossip])
    {:noreply, new_socket}
  end

  defp assign_step(socket, step) do
    assign(
      socket,
      button_text: button_texts(step),
      button_class: button_classes(step),
      button_disabled: step in @button_disabled
    )
  end

  defp button_texts(step) do
    Map.get(
      %{
        sent: dgettext("backoffice_dataset", "Sent"),
        sending: dgettext("backoffice_dataset", "Sending")
      },
      step,
      dgettext("backoffice_dataset", "Send welcome email to contacts")
    )
  end

  defp button_classes(step) do
    Map.get(
      %{
        sent: "button success",
        sending: "button button-outlined secondary"
      },
      step,
      "button"
    )
  end
end
