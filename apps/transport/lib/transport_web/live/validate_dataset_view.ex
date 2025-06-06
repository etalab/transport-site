defmodule TransportWeb.Live.ValidateDatasetView do
  use Phoenix.LiveView
  alias DB.Dataset
  use Gettext, backend: TransportWeb.Gettext
  require Logger

  @button_disabled [:validated, :validating]

  def render(assigns) do
    ~H"""
    <button class={@button_class} phx-click="validate_dataset" disabled={@button_disabled}>
      <%= @button_text %>
    </button>
    """
  end

  def mount(_params, %{"dataset_id" => dataset_id, "locale" => locale}, socket) do
    Gettext.put_locale(locale)

    new_socket =
      socket
      |> assign(dataset_id: dataset_id)
      |> assign_step(:first)

    {:ok, new_socket}
  end

  def handle_event("validate_dataset", _value, socket) do
    send(self(), {:validate, socket.assigns.dataset_id})

    {:noreply, assign_step(socket, :validating)}
  end

  def handle_info({:validate, dataset_id}, socket) do
    new_socket =
      case Dataset.validate(dataset_id, force_validation: true) do
        {:ok, _} ->
          assign_step(socket, :validated)
      end

    Process.send_after(self(), :display_form, 30_000)
    {:noreply, new_socket}
  end

  def handle_info(:display_form, socket) do
    {:noreply, assign_step(socket, :display_form)}
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
        validated: dgettext("backoffice_dataset", "Validated"),
        validating: dgettext("backoffice_dataset", "Validating")
      },
      step,
      dgettext("backoffice_dataset", "Validate")
    )
  end

  defp button_classes(step) do
    Map.get(
      %{
        validated: "button success",
        validating: "button button-outlined secondary"
      },
      step,
      "button"
    )
  end
end
