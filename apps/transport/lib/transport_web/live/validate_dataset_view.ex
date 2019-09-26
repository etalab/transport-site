defmodule TransportWeb.Live.ValidateDatasetView do
    use Phoenix.LiveView
    alias Transport.Dataset
    import TransportWeb.Gettext, only: [dgettext: 2]
    require Logger

    def render(%{step: :validated} = assigns) do
        Logger.debug "validated"
        ~L"""
        <%= dgettext("backoffice_dataset", "Validated") %>
        """
    end
    def render(%{step: :error} = assigns) do
        ~L"""
        <%= dgettext("backoffice_dataset", "Error") %>
        """
    end
    def render(%{step: :validating} = assigns) do
        ~L"""
        <button class="button" disabled>
        <%= dgettext("backoffice_dataset", "Validating") %>
        </button>
        """
    end
    def render(assigns) do
        ~L"""
        <button class="button" phx-click="validate_dataset">
        <%= dgettext("backoffice_dataset", "Validate") %>
        </button>
        """
    end

    def mount(%{dataset_id: dataset_id, locale: locale}, socket) do
        Gettext.put_locale(locale)
        {:ok, assign(socket, dataset_id: dataset_id)}
    end

    def handle_event("validate_dataset", _value, socket) do
        send(self(), {:validate, socket.assigns.dataset_id})

        {:noreply, assign(socket, step: :validating)}
    end

    def handle_info({:validate, dataset_id}, socket) do
        new_socket =
          case Dataset.validate(dataset_id) do
            {:ok, _} ->
                assign(socket, step: :validated)
            {:error, error} ->
                Logger.error error
                assign(socket, step: :error)
          end

        Process.send_after(self(), :display_form, 30_000)
        {:noreply, new_socket}
    end

    def handle_info(:display_form, socket) do
        {:noreply, assign(socket, step: :display_form)}
    end
end
