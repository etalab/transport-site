defmodule Transport.IRVE.MapPayload do
  @moduledoc """
  Build the marker payload pushed to the IRVE debug map hook.

  - Joins static rows with the first matching dynamic row to derive a state
    (en_service / occupe / hors_service / inconnu / no_dynamic).
  - Groups static rows by rounded coordinates and applies a sunflower spread
    to reveal duplicates at the same position.
  """

  @sunflower_radius_m 8
  @coord_round_decimals 5

  @doc "Returns a list of marker maps ready to be JSON-serialized to the client."
  @spec build(list(map()), list(map())) :: list(map())
  def build(static_rows, dynamic_rows) do
    dyn_by_id = index_first_dynamic(dynamic_rows)

    static_rows
    |> Enum.flat_map(&prepare_marker(&1, dyn_by_id))
    |> Enum.group_by(&{&1.lat_key, &1.lon_key})
    |> Enum.flat_map(fn {_key, group} -> sunflower(group) end)
  end

  defp index_first_dynamic(dynamic_rows) do
    Enum.reduce(dynamic_rows, %{}, fn row, acc ->
      Map.put_new(acc, row["id_pdc_itinerance"], row)
    end)
  end

  defp prepare_marker(static_row, dyn_by_id) do
    with {lat, _} <- Float.parse(static_row["consolidated_latitude"] || ""),
         {lon, _} <- Float.parse(static_row["consolidated_longitude"] || "") do
      id = static_row["id_pdc_itinerance"]
      dyn = Map.get(dyn_by_id, id)
      etat = classify(dyn)

      [
        %{
          id: id,
          lat0: lat,
          lon0: lon,
          lat_key: Float.round(lat, @coord_round_decimals),
          lon_key: Float.round(lon, @coord_round_decimals),
          nom_station: static_row["nom_station"] || "",
          nom_amenageur: static_row["nom_amenageur"] || "",
          nom_operateur: static_row["nom_operateur"] || "",
          organization: static_row["datagouv_organization_or_owner"] || "",
          dataset_title: static_row["dataset_title"] || "",
          etat: etat,
          has_dynamic: not is_nil(dyn)
        }
      ]
    else
      _ -> []
    end
  end

  defp classify(nil), do: "no_dynamic"

  defp classify(%{"etat_pdc" => etat, "occupation_pdc" => occ}) do
    cond do
      etat in ~w(hors_service Hors_service) -> "hors_service"
      occ in ~w(occupe Occupé) -> "occupe"
      etat in ~w(en_service En_service) -> "en_service"
      true -> "inconnu"
    end
  end

  defp sunflower([single]) do
    [single |> Map.put(:lat, single.lat0) |> Map.put(:lon, single.lon0) |> Map.put(:group_size, 1) |> drop_keys()]
  end

  defp sunflower(group) do
    n = length(group)

    group
    |> Enum.with_index()
    |> Enum.map(fn {marker, i} ->
      {dlat, dlon} = offset(marker.lat0, @sunflower_radius_m, 2 * :math.pi() * i / n)

      marker
      |> Map.put(:lat, marker.lat0 + dlat)
      |> Map.put(:lon, marker.lon0 + dlon)
      |> Map.put(:group_size, n)
      |> drop_keys()
    end)
  end

  defp offset(lat, radius_m, angle) do
    dlat = radius_m * :math.sin(angle) / 111_320.0
    dlon = radius_m * :math.cos(angle) / (111_320.0 * :math.cos(:math.pi() * lat / 180.0))
    {dlat, dlon}
  end

  defp drop_keys(m), do: Map.drop(m, [:lat_key, :lon_key])
end
