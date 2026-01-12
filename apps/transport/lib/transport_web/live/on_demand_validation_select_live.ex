defmodule TransportWeb.Live.OnDemandValidationSelectLive do
  @moduledoc """
  This LiveView is in charge of displaying a select input to choose
  the type of data to validate. According to the type of data
  selected, display appropriate input fields (file upload,
  text inputs etc.)
  """
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  use Gettext, backend: TransportWeb.Gettext
  import TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers

  @params [:type, :selected_tile, :selected_subtile, :url, :feed_url]

  def mount(_params, %{"locale" => locale} = _session, socket) do
    Gettext.put_locale(locale)

    {:ok,
     socket
     |> socket_data(
       Map.merge(
         %{
           trigger_submit: false,
           tiles: [
             {"public-transit",
              %{
                icon: static_path(socket, "/images/icons/bus.svg"),
                title: dgettext("validations", "Public transit"),
                subtitle: "GTFS, GTFS-RT, NeTEx",
                sub_tiles: ["GTFS", "GTFS-Flex", "GTFS-RT", "NeTEx"] |> Enum.map(&{&1, String.downcase(&1)})
              }},
             {"vehicles-sharing",
              %{
                icon: static_path(socket, "/images/icons/vehicles-sharing.svg"),
                title: dgettext("validations", "Vehicles sharing"),
                subtitle: "GBFS, NeTEx",
                sub_tiles: ["GBFS", "NeTEx"] |> Enum.map(&{&1, String.downcase(&1)})
              }},
             {"schemas",
              %{
                icon: static_path(socket, "/images/icons/infos.svg"),
                title: dgettext("validations", "Road mobility and bike"),
                subtitle: dgettext("validations", "IRVE, ZFE, carpooling, bike data etc."),
                sub_tiles:
                  Transport.Schemas.Wrapper.transport_schemas()
                  |> Enum.map(fn {k, v} -> {Map.fetch!(v, "title"), k} end)
                  |> Enum.sort_by(&elem(&1, 0))
              }}
           ]
         },
         Map.new(@params, fn k -> {k, nil} end)
       )
     )}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, socket |> socket_data(params |> params_to_assigns())}
  end

  def self_path(socket) do
    live_path(
      socket,
      __MODULE__,
      socket.assigns |> Map.take(@params) |> Map.reject(fn {_, v} -> v in ["", nil] end)
    )
  end

  def socket_data(socket, data) do
    socket = socket |> assign(data)
    socket |> assign(input_type: determine_input_type(socket.assigns.type))
  end

  def determine_input_type(type) when type in ["gbfs"], do: "link"
  def determine_input_type(type) when type in ["gtfs-rt"], do: "gtfs-rt"
  def determine_input_type(_), do: "file"

  def handle_event("form_changed", %{"upload" => params, "_target" => target}, socket) do
    socket =
      socket
      |> socket_data(params |> params_to_assigns())
      |> assign(trigger_submit: "file" in target)

    {:noreply, socket |> push_patch(to: self_path(socket))}
  end

  def handle_event("select_tile", %{"tile" => tile}, socket) do
    socket = socket |> assign(selected_tile: tile, selected_subtile: nil, type: nil)
    {:noreply, socket |> push_patch(to: self_path(socket))}
  end

  def handle_event("select_subtile", %{"tile" => tile}, socket) do
    socket = socket |> socket_data(type: tile, selected_subtile: tile)
    {:noreply, socket |> push_patch(to: self_path(socket))}
  end

  def icon(type) do
    Map.get(
      %{
        "gtfs" => "/images/icons/bus.svg",
        "gtfs-rt" => "/images/icons/bus.svg",
        "gtfs-flex" => "/images/icons/bus.svg",
        "netex" => "/images/icons/bus.svg",
        "gbfs" => "/images/icons/vehicles-sharing.svg",
        "etalab/schema-amenagements-cyclables" => "/images/icons/bike-data.svg",
        "etalab/schema-stationnement-cyclable" => "/images/icons/bike-data.svg",
        "etalab/schema-irve-dynamique" => "/images/icons/charge-station.svg",
        "etalab/schema-irve-statique" => "/images/icons/charge-station.svg",
        "etalab/schema-lieux-covoiturage" => "/images/icons/carpooling-areas.svg",
        "etalab/schema-zfe" => "/images/icons/roads.svg",
        "etalab/schema-stationnement" => "/images/icons/car.svg"
      },
      type,
      "/images/icons/infos.svg"
    )
  end

  def params_to_assigns(params) do
    params
    |> Map.take(Enum.map(@params, &to_string/1))
    |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
  end
end
