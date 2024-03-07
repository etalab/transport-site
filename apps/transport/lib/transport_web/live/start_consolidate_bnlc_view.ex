defmodule TransportWeb.Live.SendConsolidateBNLCView do
  # Very similar to `TransportWeb.Live.SendNowOnNAPNotificationView`
  use Phoenix.LiveView
  @button_disabled [:dispatched, :sent]

  def render(assigns) do
    ~H"""
    <button class={@button_class} phx-click="dispatch_job" disabled={@button_disabled}>
      <%= @button_text %>
    </button>
    """
  end

  def mount(_params, %{"button_texts" => _, "button_default_class" => _, "job_args" => _} = session, socket) do
    sessions_params = Map.new(session, fn {k, v} -> {String.to_existing_atom(k), v} end)
    {:ok, socket |> assign(sessions_params) |> assign_step(:first)}
  end

  def handle_event("dispatch_job", _value, socket) do
    send(self(), :dispatch)
    {:noreply, socket}
  end

  def handle_info(:dispatch, %Phoenix.LiveView.Socket{assigns: %{job_args: job_args}} = socket) do
    new_socket =
      case job_args |> Transport.Jobs.ConsolidateBNLCJob.new() |> Oban.insert() do
        {:ok, %Oban.Job{id: job_id}} ->
          send(self(), {:wait_for_completion, job_id})
          assign_step(socket, :dispatched)
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
    # Go back to the first state after 60s to let the end user consolidate again if they wish
    Process.send_after(self(), :reset, :timer.seconds(60))
    {:noreply, new_socket}
  end

  def handle_info(:reset, socket) do
    {:noreply, socket |> assign_step(:first)}
  end

  defp assign_step(%Phoenix.LiveView.Socket{} = socket, step) do
    assign(
      socket,
      button_text: button_texts(socket, step),
      button_class: button_classes(socket, step),
      button_disabled: step in @button_disabled
    )
  end

  defp button_texts(%Phoenix.LiveView.Socket{assigns: %{button_texts: button_texts}}, step) do
    Map.get(
      button_texts,
      step,
      Map.fetch!(button_texts, :default)
    )
  end

  defp button_classes(%Phoenix.LiveView.Socket{assigns: %{button_default_class: button_default_class}}, step) do
    Map.get(
      %{
        sent: "button success",
        dispatched: "button button-outlined secondary"
      },
      step,
      button_default_class
    )
  end
end
