defmodule TransportWeb.Live.OnDemandValidationSelectLive do
  @moduledoc """
  This LiveView is in charge of displaying a select input to choose
  the type of data to validate. According to the type of data
  selected, display appropriate input fields (file upload,
  text inputs etc.)
  """
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import TransportWeb.Gettext
  import TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers
  import TransportWeb.ValidationController, only: [select_options: 0]

  def mount(_params, %{"locale" => locale} = _session, socket) do
    Gettext.put_locale(locale)

    {:ok,
     socket
     |> socket_data(%{
       trigger_submit: false,
       select_options: select_options(),
       changeset: cast(%{})
     })}
  end

  defp cast(params) do
    Ecto.Changeset.cast(
      {%{url: "", type: "", feed_url: ""}, %{url: :string, type: :string, feed_url: :string}},
      params,
      [:url, :type, :feed_url]
    )
  end

  def handle_params(params, _uri, socket) do
    {:noreply, socket |> socket_data(%{changeset: cast(params)})}
  end

  def self_path(socket) do
    fields = form_fields(socket)
    live_path(socket, __MODULE__, fields |> Map.reject(fn {_, v} -> v in ["", nil] end))
  end

  def socket_data(socket, data \\ nil) do
    socket = socket |> assign(data || %{})

    socket |> assign(input_type: determine_input_type(form_value(socket, :type)))
  end

  def determine_input_type(type) when type in ["gbfs"], do: "link"
  def determine_input_type(type) when type in ["gtfs-rt"], do: "gtfs-rt"
  def determine_input_type(_), do: "file"

  def handle_event("form_changed", %{"upload" => params, "_target" => target}, socket) do
    socket = socket |> socket_data(%{changeset: cast(params), trigger_submit: "file" in target})
    {:noreply, socket |> push_patch(to: self_path(socket))}
  end

  defp form_value(socket, field) do
    Ecto.Changeset.get_field(socket_value(socket, :changeset), field)
  end

  defp form_fields(socket) do
    changeset = socket_value(socket, :changeset)
    Map.merge(changeset.data(), changeset.changes())
  end

  defp socket_value(%Phoenix.LiveView.Socket{assigns: assigns}, key), do: Map.get(assigns, key)
end
