defmodule TransportWeb.Live.ValidateDatasetView do
  use Phoenix.LiveView
  alias DB.Dataset
  use Gettext, backend: TransportWeb.Gettext

  @button_disabled [:validated, :validating]

  def render(assigns) do
    ~H"""
    <button
      phx-click="validate_dataset"
      role="menuitem"
      class={"ctx-menu__validate #{state_class(@step)}"}
    >
      <i class={"fas fa-#{icon_for_state(@step)}"}></i>
      {text_for_state(@step)}
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
      step: step,
      button_disabled: step in @button_disabled
    )
  end

  defp icon_for_state(:validated), do: "check"
  defp icon_for_state(:validating), do: "spinner fa-spin"
  defp icon_for_state(_), do: "check"

  defp text_for_state(step) do
    Map.get(
      %{
        validated: dgettext("backoffice_dataset", "Validated"),
        validating: dgettext("backoffice_dataset", "Validation in progress…")
      },
      step,
      dgettext("backoffice_dataset", "Validate")
    )
  end

  defp state_class(:validating), do: "ctx-menu__validate--pending"
  defp state_class(:validated), do: "ctx-menu__validate--success"
  defp state_class(_), do: ""
end
