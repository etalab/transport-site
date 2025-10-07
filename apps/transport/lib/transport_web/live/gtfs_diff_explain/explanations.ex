defmodule TransportWeb.GTFSDiffExplain.Explanations do
  @moduledoc """
  Updates explanations.
  """
  use Gettext, backend: TransportWeb.Gettext

  def diff_explanations(diffs) do
    diffs
    |> Enum.flat_map(fn diff ->
      diff =
        diff
        |> Map.update("initial_value", %{}, &try_jason_decode/1)
        |> Map.update("new_value", %{}, &try_jason_decode/1)
        |> Map.update("identifier", %{}, &try_jason_decode/1)

      []
      |> explanation_update_stop_name(diff)
      |> explanation_stop_wheelchair_access(diff)
      |> explanation_update_stop_position(diff)
      |> explanation_route_color(diff)
      |> explanation_route_text_color(diff)
      |> explanation_route_short_name(diff)
      |> explanation_route_long_name(diff)
      |> explanation_route_type(diff)
      |> explanation_stop_location_type(diff)
      |> explanation_agency_url(diff)
      |> explanation_agency_fare_url(diff)
      |> explanation_agency_phone(diff)
      |> explanation_trip_headsign(diff)
    end)
  end

  defp explanation_update_stop_name(
         explanations,
         %{
           "action" => "update",
           "file" => "stops.txt",
           "target" => "row",
           "identifier" => %{"stop_id" => stop_id},
           "new_value" => %{"stop_name" => new_stop_name},
           "initial_value" => %{"stop_name" => initial_stop_name}
         }
       ) do
    [
      %{
        file: "stops.txt",
        type: "stop_name",
        message: dgettext("gtfs-diff", "Stop %{stop_id} has been renamed", stop_id: stop_id),
        before: initial_stop_name,
        after: new_stop_name,
        sort_key: initial_stop_name
      }
      | explanations
    ]
  end

  defp explanation_update_stop_name(explanations, _), do: explanations

  defp explanation_stop_wheelchair_access(
         explanations,
         %{
           "action" => "update",
           "file" => "stops.txt",
           "target" => "row",
           "identifier" => %{"stop_id" => stop_id},
           "new_value" => %{"wheelchair_boarding" => new_wheelchair_boarding},
           "initial_value" => %{"wheelchair_boarding" => initial_wheelchair_boarding}
         }
       )
       when new_wheelchair_boarding in ["1", "2"] do
    [
      %{
        file: "stops.txt",
        type: "wheelchair_boarding",
        message: dgettext("gtfs-diff", "Wheelchair_boarding updated for stop %{stop_id}", stop_id: stop_id),
        before: initial_wheelchair_boarding,
        after: new_wheelchair_boarding,
        sort_key: stop_id
      }
      | explanations
    ]
  end

  defp explanation_stop_wheelchair_access(explanations, _), do: explanations

  defp explanation_update_stop_position(
         explanations,
         %{
           "action" => "update",
           "file" => "stops.txt",
           "target" => "row",
           "identifier" => %{"stop_id" => stop_id},
           "new_value" => %{"stop_lat" => lat2, "stop_lon" => lon2},
           "initial_value" => %{"stop_lat" => lat1, "stop_lon" => lon1}
         }
       ) do
    {lat1, _} = parse_latitude_longitude(lat1)
    {lon1, _} = parse_latitude_longitude(lon1)
    {lat2, _} = parse_latitude_longitude(lat2)
    {lon2, _} = parse_latitude_longitude(lon2)

    distance = round(curvilinear_abscissa({lat1, lon1}, {lat2, lon2}))

    if distance >= 2 do
      [
        %{
          file: "stops.txt",
          type: "stop_position",
          message:
            dgettext("gtfs-diff", "Stop %{stop_id} has been moved by %{distance}m",
              stop_id: stop_id,
              distance: distance
            ),
          before: "(#{lat1}, #{lon1})",
          after: "(#{lat2}, #{lon2})",
          sort_key: -distance
        }
        | explanations
      ]
    else
      explanations
    end
  end

  defp explanation_update_stop_position(explanations, _), do: explanations

  def explanation_route_color(
        explanations,
        %{
          "action" => "update",
          "file" => "routes.txt",
          "target" => "row",
          "identifier" => %{"route_id" => route_id},
          "new_value" => %{"route_color" => new_route_color},
          "initial_value" => %{"route_color" => initial_route_color}
        }
      ) do
    if different_colors?(initial_route_color, new_route_color) do
      [
        %{
          file: "routes.txt",
          type: "route_color",
          message: dgettext("gtfs-diff", "Color has been updated for route %{route_id}", route_id: route_id),
          before: "##{initial_route_color}",
          after: "##{new_route_color}",
          sort_key: route_id
        }
        | explanations
      ]
    else
      explanations
    end
  end

  def explanation_route_color(explanations, _), do: explanations

  def explanation_route_text_color(
        explanations,
        %{
          "action" => "update",
          "file" => "routes.txt",
          "target" => "row",
          "identifier" => %{"route_id" => route_id},
          "new_value" => %{"route_text_color" => new_route_text_color},
          "initial_value" => %{"route_text_color" => initial_route_text_color}
        }
      ) do
    if different_colors?(initial_route_text_color, new_route_text_color) do
      [
        %{
          file: "routes.txt",
          type: "route_text_color",
          message: dgettext("gtfs-diff", "Text color has been updated for route %{route_id}", route_id: route_id),
          before: "##{initial_route_text_color}",
          after: "##{new_route_text_color}",
          sort_key: route_id
        }
        | explanations
      ]
    else
      explanations
    end
  end

  def explanation_route_text_color(explanations, _), do: explanations

  defp different_colors?(initial_color, new_color), do: String.downcase(initial_color) != String.downcase(new_color)

  defp explanation_route_short_name(
         explanations,
         %{
           "action" => "update",
           "file" => "routes.txt",
           "target" => "row",
           "identifier" => %{"route_id" => route_id},
           "new_value" => %{"route_short_name" => new_route_short_name},
           "initial_value" => %{"route_short_name" => initial_route_short_name}
         }
       ) do
    [
      %{
        file: "routes.txt",
        type: "route_short_name",
        message: dgettext("gtfs-diff", "Route short name has been updated for route %{route_id}", route_id: route_id),
        before: initial_route_short_name,
        after: new_route_short_name,
        sort_key: route_id
      }
      | explanations
    ]
  end

  defp explanation_route_short_name(explanations, _), do: explanations

  defp explanation_route_long_name(
         explanations,
         %{
           "action" => "update",
           "file" => "routes.txt",
           "target" => "row",
           "identifier" => %{"route_id" => route_id},
           "new_value" => %{"route_long_name" => new_route_long_name},
           "initial_value" => %{"route_long_name" => initial_route_long_name}
         }
       ) do
    [
      %{
        file: "routes.txt",
        type: "route_long_name",
        message: dgettext("gtfs-diff", "Route long name has been updated for route %{route_id}", route_id: route_id),
        before: initial_route_long_name,
        after: new_route_long_name,
        sort_key: route_id
      }
      | explanations
    ]
  end

  defp explanation_route_long_name(explanations, _), do: explanations

  defp explanation_route_type(
         explanations,
         %{
           "action" => "update",
           "file" => "routes.txt",
           "target" => "row",
           "identifier" => %{"route_id" => route_id},
           "new_value" => %{"route_type" => new_route_type},
           "initial_value" => %{"route_type" => initial_route_type}
         }
       ) do
    [
      %{
        file: "routes.txt",
        type: "route_type",
        message: dgettext("gtfs-diff", "Route type has been updated for route %{route_id}", route_id: route_id),
        before: initial_route_type,
        after: new_route_type,
        sort_key: route_id
      }
      | explanations
    ]
  end

  defp explanation_route_type(explanations, _), do: explanations

  defp explanation_stop_location_type(
         explanations,
         %{
           "action" => "update",
           "file" => "stops.txt",
           "target" => "row",
           "identifier" => %{"stop_id" => stop_id},
           "new_value" => %{"location_type" => new_location_type},
           "initial_value" => %{"location_type" => initial_location_type}
         }
       ) do
    [
      %{
        file: "stops.txt",
        type: "location_type",
        message: dgettext("gtfs-diff", "Location type for stop %{stop_id} has been changed", stop_id: stop_id),
        before: initial_location_type,
        after: new_location_type,
        sort_key: stop_id
      }
      | explanations
    ]
  end

  defp explanation_stop_location_type(explanations, _), do: explanations

  defp explanation_agency_url(
         explanations,
         %{
           "action" => "update",
           "file" => "agency.txt",
           "target" => "row",
           "identifier" => %{"agency_id" => agency_id},
           "new_value" => %{"agency_url" => new_agency_url},
           "initial_value" => %{"agency_url" => initial_agency_url}
         }
       ) do
    [
      %{
        file: "agency.txt",
        type: "agency_url",
        message: dgettext("gtfs-diff", "Agency URL for agency %{agency_id} has been changed", agency_id: agency_id),
        before: initial_agency_url,
        after: new_agency_url,
        sort_key: agency_id
      }
      | explanations
    ]
  end

  defp explanation_agency_url(explanations, _), do: explanations

  defp explanation_agency_fare_url(
         explanations,
         %{
           "action" => "update",
           "file" => "agency.txt",
           "target" => "row",
           "identifier" => %{"agency_id" => agency_id},
           "new_value" => %{"agency_fare_url" => new_agency_fare_url},
           "initial_value" => %{"agency_fare_url" => initial_agency_fare_url}
         }
       ) do
    [
      %{
        file: "agency.txt",
        type: "agency_fare_url",
        message:
          dgettext("gtfs-diff", "Agency fare URL for agency %{agency_id} has been changed", agency_id: agency_id),
        before: initial_agency_fare_url,
        after: new_agency_fare_url,
        sort_key: agency_id
      }
      | explanations
    ]
  end

  defp explanation_agency_fare_url(explanations, _), do: explanations

  defp explanation_agency_phone(
         explanations,
         %{
           "action" => "update",
           "file" => "agency.txt",
           "target" => "row",
           "identifier" => %{"agency_id" => agency_id},
           "new_value" => %{"agency_phone" => new_agency_phone},
           "initial_value" => %{"agency_phone" => initial_agency_phone}
         }
       ) do
    [
      %{
        file: "agency.txt",
        type: "agency_phone",
        message: dgettext("gtfs-diff", "Agency phone for agency %{agency_id} has been changed", agency_id: agency_id),
        before: initial_agency_phone,
        after: new_agency_phone,
        sort_key: agency_id
      }
      | explanations
    ]
  end

  defp explanation_agency_phone(explanations, _), do: explanations

  defp explanation_trip_headsign(
         explanations,
         %{
           "action" => "update",
           "file" => "trips.txt",
           "target" => "row",
           "identifier" => %{"trip_id" => trip_id},
           "new_value" => %{"trip_headsign" => new_trip_headsign},
           "initial_value" => %{"trip_headsign" => initial_trip_headsign}
         }
       ) do
    [
      %{
        file: "trips.txt",
        type: "trip_headsign",
        message: dgettext("gtfs-diff", "Headsign for trip %{trip_id} has been changed", trip_id: trip_id),
        before: initial_trip_headsign,
        after: new_trip_headsign,
        sort_key: trip_id
      }
      | explanations
    ]
  end

  defp explanation_trip_headsign(explanations, _), do: explanations

  @doc """
    From https://geodesie.ign.fr/contenu/fichiers/Distance_longitude_latitude.pdf:

    Si l’on considère deux points A et B sur la sphère, de
    latitudes ϕA et ϕB et de longitudes λA et λB , alors la
    distance angulaire en radians S A-B entre A et B est
    donnée par la relation fondamentale de trigonométrie
    sphérique, utilisant dλ = λB – λA :

    S A-B = arccos (sin ϕA sin ϕB + cos ϕA cos ϕB cos dλ)

    La distance S en mètres, s’obtient en multipliant S A-B
    par un rayon de la Terre conventionnel (6 378 137 mètres par exemple).

    iex> curvilinear_abscissa({46.605513, 0.275126}, {46.605348, 0.275881}) |> round()
    61
    iex> curvilinear_abscissa({47.6355, 6.1649}, {47.6355, 6.1649})
    0.0
    iex> curvilinear_abscissa({47.6355, 6.1687}, {47.6355, 6.1687})
    0.0
    iex> curvilinear_abscissa({47.6355, 6.143}, {47.6355, 6.143})
    0.0
    iex> curvilinear_abscissa({47.6333, 6.1015}, {47.6333, 6.1015})
    0.0
    iex> curvilinear_abscissa({47.6547, 6.1255}, {47.6547, 6.1255})
    0.0
    iex> curvilinear_abscissa({47.632, 6.1142}, {47.632, 6.1142})
    0.0
  """
  def curvilinear_abscissa({lat1, lon1}, {lat2, lon2}) do
    # Semi-major axis of WGS 84
    r = 6_378_137

    lat1r = deg2rad(lat1)
    lon1r = deg2rad(lon1)
    lat2r = deg2rad(lat2)
    lon2r = deg2rad(lon2)

    dlon = lon2r - lon1r

    # clamping is necessary unfortunately as they can be rounding errors
    r *
      :math.acos(
        clamp(:math.sin(lat1r) * :math.sin(lat2r) + :math.cos(lat1r) * :math.cos(lat2r) * :math.cos(dlon), -1, 1)
      )
  end

  defp clamp(number, minimum, maximum) do
    number
    |> max(minimum)
    |> min(maximum)
  end

  defp deg2rad(deg), do: deg * :math.pi() / 180.0

  def try_jason_decode(""), do: nil
  def try_jason_decode(input), do: Jason.decode!(input)

  @doc """
  iex> parse_latitude_longitude("47.6355")
  {47.6355, ""}
  iex> parse_latitude_longitude("   47.6355")
  {47.6355, ""}
  iex> parse_latitude_longitude("47.6355   ")
  {47.6355, ""}
  """
  def parse_latitude_longitude(value) do
    value
    |> String.trim()
    |> Float.parse()
  end
end
