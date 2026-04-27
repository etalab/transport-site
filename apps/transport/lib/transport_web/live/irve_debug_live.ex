defmodule TransportWeb.Live.IRVEDebugLive do
  @moduledoc """
  Public debug page for the IRVE consolidation fluxes.

  Consumes the public proxy URLs (static dedup / static avec doublons /
  dynamique) so the page also acts as a self-documenting reuse demo.

  - `bbox=minlat,minlon,maxlat,maxlon` and `dedup` are URL params (push_patch).
  - "Around here" geolocates and seeds a 500m bbox.
  - Pan/zoom on the map updates the bbox in the URL — permalinks reproduce
    the exact view.
  - The dynamic table re-fetches every #{div(10_000, 1000)}s and flashes
    cells whose value changed since the previous tick; matching markers on
    the map flash a yellow halo.
  """
  use Phoenix.LiveView
  require Explorer.DataFrame, as: DF
  alias Transport.IRVE.PublicFluxClient

  @default_radius_m 500
  @dynamic_tick_ms 10_000

  @static_visible_columns ~w(
    id_pdc_itinerance nom_station adresse_station nom_amenageur nom_operateur
    puissance_nominale consolidated_longitude consolidated_latitude
    datagouv_dataset_id datagouv_resource_id datagouv_organization_or_owner dataset_title
  )

  @dynamic_visible_columns ~w(
    id_pdc_itinerance origin horodatage etat_pdc occupation_pdc
    etat_prise_type_2 etat_prise_type_combo_ccs etat_prise_type_chademo etat_prise_type_ef
  )

  @blinkable_dynamic_fields ~w(horodatage etat_pdc occupation_pdc
    etat_prise_type_2 etat_prise_type_combo_ccs etat_prise_type_chademo etat_prise_type_ef)

  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@dynamic_tick_ms, :tick_dynamic)

    {:ok,
     assign(socket,
       bbox: nil,
       dedup: true,
       static_rows: [],
       dynamic_rows: [],
       prev_dynamic: %{},
       static_visible_columns: @static_visible_columns,
       dynamic_visible_columns: @dynamic_visible_columns,
       error: nil,
       last_dynamic_refresh: nil,
       patch_origin: :external
     )}
  end

  def handle_params(params, _uri, socket) do
    bbox = parse_bbox(params["bbox"])
    origin = socket.assigns[:patch_origin] || :external

    socket =
      socket
      |> assign(bbox: bbox, dedup: params["dedup"] != "false", patch_origin: :external)
      |> reload_static()
      |> reload_dynamic(blink: false)
      |> push_map_update(fit: origin == :external)

    {:noreply, socket}
  end

  def handle_event("locate-here", %{"lat" => lat, "lon" => lon}, socket) do
    {lat, _} = Float.parse(lat)
    {lon, _} = Float.parse(lon)
    bbox = bbox_around(lat, lon, @default_radius_m)
    {:noreply, push_patch_origin(socket, %{bbox: bbox}, :external)}
  end

  def handle_event("viewport-changed", %{"bbox" => bbox_str}, socket) do
    case parse_bbox(bbox_str) do
      nil -> {:noreply, socket}
      bbox -> {:noreply, push_patch_origin(socket, %{bbox: bbox}, :viewport)}
    end
  end

  def handle_event("toggle-dedup", _, socket) do
    {:noreply, push_patch_origin(socket, %{dedup: not socket.assigns.dedup}, :external)}
  end

  def handle_event("clear", _, socket) do
    {:noreply, push_patch(socket, to: "/explore/irve")}
  end

  def handle_info(:tick_dynamic, socket) do
    {:noreply, socket |> reload_dynamic(blink: true) |> push_map_update(fit: false)}
  end

  defp reload_static(%{assigns: %{bbox: nil}} = socket), do: assign(socket, static_rows: [], error: nil)

  defp reload_static(socket) do
    %{bbox: bbox, dedup: dedup} = socket.assigns
    flavour = if dedup, do: :dedup, else: :with_doublons

    rows =
      PublicFluxClient.fetch_static(flavour)
      |> filter_bbox(bbox)
      |> df_to_rows(@static_visible_columns)
      |> sort_static_rows()

    assign(socket, static_rows: rows, error: nil)
  rescue
    e -> assign(socket, error: "Static flux: #{Exception.message(e)}", static_rows: [])
  end

  defp reload_dynamic(%{assigns: %{static_rows: []}} = socket, _opts) do
    assign(socket, dynamic_rows: [], prev_dynamic: %{})
  end

  defp reload_dynamic(socket, opts) do
    ids = MapSet.new(socket.assigns.static_rows, & &1["id_pdc_itinerance"])

    new_rows =
      PublicFluxClient.fetch_dynamic()
      |> filter_ids(ids)
      |> df_to_rows(@dynamic_visible_columns)
      |> sort_dynamic_rows()

    socket =
      socket
      |> maybe_push_blink(new_rows, opts[:blink])
      |> maybe_push_flash(new_rows, opts[:blink])

    assign(socket,
      dynamic_rows: new_rows,
      prev_dynamic: index_by_id(new_rows),
      last_dynamic_refresh: DateTime.utc_now()
    )
  rescue
    e -> assign(socket, error: "Dynamic flux: #{Exception.message(e)}", dynamic_rows: [])
  end

  defp maybe_push_blink(socket, _rows, blink) when blink in [false, nil], do: socket

  defp maybe_push_blink(socket, new_rows, true) do
    prev = socket.assigns.prev_dynamic
    cells = changed_cells(prev, new_rows)
    if cells == [], do: socket, else: push_event(socket, "irve:blink", %{cells: cells})
  end

  defp maybe_push_flash(socket, _rows, blink) when blink in [false, nil], do: socket

  defp maybe_push_flash(socket, new_rows, true) do
    ids = changed_ids(socket.assigns.prev_dynamic, new_rows)
    if ids == [], do: socket, else: push_event(socket, "irve:map:flash", %{ids: ids})
  end

  defp changed_cells(prev, new_rows) do
    for row <- new_rows,
        id = row["id_pdc_itinerance"],
        field <- @blinkable_dynamic_fields,
        prev_row = Map.get(prev, id),
        prev_row && Map.get(prev_row, field) != Map.get(row, field) do
      %{id: id, field: field}
    end
  end

  defp changed_ids(prev, new_rows) do
    for row <- new_rows,
        id = row["id_pdc_itinerance"],
        prev_row = Map.get(prev, id),
        prev_row && Enum.any?(@blinkable_dynamic_fields, &(Map.get(prev_row, &1) != Map.get(row, &1))),
        uniq: true do
      id
    end
  end

  defp push_map_update(%{assigns: %{bbox: nil}} = socket, _opts), do: socket

  defp push_map_update(socket, opts) do
    markers =
      Transport.IRVE.MapPayload.build(socket.assigns.static_rows, socket.assigns.dynamic_rows)

    push_event(socket, "irve:map:markers", %{
      markers: markers,
      bbox: bbox_to_list(socket.assigns.bbox),
      fit: Keyword.get(opts, :fit, false)
    })
  end

  defp index_by_id(rows), do: Map.new(rows, &{&1["id_pdc_itinerance"], &1})

  defp sort_static_rows(rows) do
    Enum.sort_by(rows, &{&1["id_pdc_itinerance"], &1["datagouv_resource_id"]})
  end

  defp sort_dynamic_rows(rows) do
    Enum.sort_by(rows, &{&1["id_pdc_itinerance"], &1["origin"], &1["horodatage"]})
  end

  defp filter_bbox(df, %{min_lat: min_lat, min_lon: min_lon, max_lat: max_lat, max_lon: max_lon}) do
    df
    |> DF.mutate(
      _lat: cast(consolidated_latitude, :float),
      _lon: cast(consolidated_longitude, :float)
    )
    |> DF.filter(
      _lat >= ^min_lat and _lat <= ^max_lat and
        _lon >= ^min_lon and _lon <= ^max_lon
    )
    |> DF.discard(["_lat", "_lon"])
  end

  defp filter_ids(df, ids) do
    rows = DF.to_rows(df, atom_keys: false)
    Enum.filter(rows, &MapSet.member?(ids, &1["id_pdc_itinerance"]))
  end

  defp df_to_rows(%Explorer.DataFrame{} = df, columns) do
    available = DF.names(df)
    kept = Enum.filter(columns, &(&1 in available))

    df
    |> DF.select(kept)
    |> DF.to_rows(atom_keys: false)
    |> Enum.map(&stringify_values/1)
  end

  defp stringify_values(map), do: Map.new(map, fn {k, v} -> {k, stringify(v)} end)
  defp stringify(nil), do: ""
  defp stringify(v) when is_binary(v), do: v
  defp stringify(v), do: to_string(v)

  defp bbox_around(lat, lon, radius_m) do
    delta_lat = radius_m / 111_320.0
    delta_lon = radius_m / (111_320.0 * :math.cos(:math.pi() * lat / 180.0))

    %{
      min_lat: lat - delta_lat,
      min_lon: lon - delta_lon,
      max_lat: lat + delta_lat,
      max_lon: lon + delta_lon
    }
  end

  defp parse_bbox(nil), do: nil

  defp parse_bbox(str) when is_binary(str) do
    with [a, b, c, d] <- String.split(str, ","),
         {min_lat, ""} <- Float.parse(a),
         {min_lon, ""} <- Float.parse(b),
         {max_lat, ""} <- Float.parse(c),
         {max_lon, ""} <- Float.parse(d),
         true <- min_lat < max_lat and min_lon < max_lon do
      %{min_lat: min_lat, min_lon: min_lon, max_lat: max_lat, max_lon: max_lon}
    else
      _ -> nil
    end
  end

  defp parse_bbox(%{} = bbox), do: bbox

  defp bbox_to_list(%{min_lat: a, min_lon: b, max_lat: c, max_lon: d}), do: [a, b, c, d]

  defp bbox_to_string(%{min_lat: a, min_lon: b, max_lat: c, max_lon: d}) do
    Enum.map_join([a, b, c, d], ",", &Float.to_string(Float.round(&1, 6)))
  end

  defp push_patch_origin(socket, overrides, origin) do
    socket
    |> assign(:patch_origin, origin)
    |> push_patch(to: build_path(socket, overrides))
  end

  defp build_path(socket, overrides) do
    base = %{bbox: socket.assigns.bbox, dedup: socket.assigns.dedup}

    query =
      base
      |> Map.merge(overrides)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(fn
        {:dedup, true} -> {"dedup", "true"}
        {:dedup, false} -> {"dedup", "false"}
        {:bbox, bbox} when is_map(bbox) -> {"bbox", bbox_to_string(bbox)}
        {k, v} -> {to_string(k), to_string(v)}
      end)
      |> URI.encode_query()

    "/explore/irve?" <> query
  end
end
