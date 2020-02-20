defmodule TransportWeb.Live.ValidateDatasetView do
  use Phoenix.LiveView
  alias DB.Dataset
  import TransportWeb.Gettext, only: [dgettext: 2]
  require Logger

  @button_disabled [:validated, :error, :validating]

  def render(assigns) do
    ~L"""
    <button class="<%= @button_class %>" phx-click="validate_dataset" <%= @button_disabled%>>
    <%= @button_text %>
    </button>
    """
  end

  def mount(%{dataset_id: dataset_id, locale: locale}, socket) do
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
      case Dataset.validate(dataset_id) do
        {:ok, _} ->
          assign_step(socket, :validated)

        {:error, error} ->
          Logger.error(error)
          assign_step(socket, :error)
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
      button_disabled: if(step in @button_disabled, do: "disabled", else: "")
    )
  end

  defp button_texts(step) do
    Map.get(
      %{
        validated: dgettext("backoffice_dataset", "Validated"),
        error: dgettext("backoffice_dataset", "Error"),
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
        error: "button secondary",
        validating: "button-outlined secondary"
      },
      step,
      "button"
    )
  end
end
