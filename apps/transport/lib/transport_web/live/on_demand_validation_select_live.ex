defmodule TransportWeb.Live.OnDemandValidationSelectLive do
  @moduledoc """
  This Live view is in charge of displaying an on demand validation:
  waiting, error and results screens.
  """
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import TransportWeb.Gettext
  import TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers
  import TransportWeb.ValidationController, only: [select_options: 0]

  @default_selected "gtfs"

  def mount(_params, %{"locale" => locale} = _session, socket) do
    Gettext.put_locale(locale)

    {:ok,
     socket
     |> socket_data(%{
       select_options: select_options(),
       changeset: Ecto.Changeset.cast({%{url: "", file: ""}, %{url: :string, file: :string}}, %{}, [:url, :file])
     })}
  end

  def handle_params(params, _uri, socket) do
    type = params["type"]
    selected = type || @default_selected
    {:noreply, socket |> socket_data(%{type: type, selected: selected})}
  end

  def self_path(socket) do
    live_path(socket, __MODULE__, %{"type" => socket_value(socket, :type)})
  end

  def socket_data(socket, data \\ nil) do
    socket = socket |> assign(data || %{})

    socket |> assign(input_type: determine_input_type(socket_value(socket, :type)))
  end

  def determine_input_type(type) when type in ["gbfs"], do: "link"
  def determine_input_type(_), do: "file"

  def handle_event("form_changed", %{"upload" => params}, socket) do
    socket = socket |> socket_data(%{type: Map.get(params, "type")})
    {:noreply, socket |> push_patch(to: self_path(socket))}
  end

  defp socket_value(%Phoenix.LiveView.Socket{assigns: assigns}, key), do: Map.get(assigns, key)
end
