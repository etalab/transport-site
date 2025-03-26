defmodule TransportWeb.GTFSDiffExplain do
  @moduledoc """
  Functions to explain and interpret GTFS Diff files
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
    end)
  end

  @doc """
  Analyses structural changes of diff, focusing on column changes and if the file has been created or deleted.

  It ignores the row changes.
  """
  def structural_changes(diffs) do
    Enum.reduce(diffs, %{}, fn action, acc ->
      if Map.get(action, "target") == "row" do
        acc
      else
        new_diff = structural_change(action)

        Map.update(acc, Map.get(action, "file"), [new_diff], &merge_diffs(new_diff, &1))
      end
    end)
  end

  defp structural_change(%{"target" => "file", "action" => action}) do
    case action do
      "add" -> :added_file
      "delete" -> :deleted_file
    end
  end

  defp structural_change(%{"target" => "column", "action" => action, "identifier" => identifier}) do
    %{"column" => column} = Jason.decode!(identifier)

    case action do
      "add" -> {:added_columns, [column]}
      "delete" -> {:deleted_columns, [column]}
    end
  end

  defp merge_diffs({column_action, _} = new_diff, diffs) do
    existing_action =
      Enum.find(diffs, fn elem ->
        case elem do
          {^column_action, _} -> true
          _ -> false
        end
      end)

    if existing_action do
      Enum.map(diffs, &merge_existing_actions(new_diff, &1))
    else
      [new_diff | diffs]
    end
  end

  defp merge_diffs(new_diff, diffs) do
    [new_diff | diffs]
  end

  defp merge_existing_actions({column_action, columns1}, elem) do
    case elem do
      {^column_action, columns2} -> {column_action, Enum.sort(columns1 ++ columns2)}
      _ -> elem
    end
  end

  @doc """
  Creates a summary of a given GTFS Diff

  iex> [
  ...> %{
  ...>   "action" => "delete",
  ...>   "file" => "agency.txt",
  ...>   "target" => "file"
  ...> },
  ...> %{
  ...>   "action" => "delete",
  ...>   "file" => "calendar.txt",
  ...>   "target" => "column"
  ...> },
  ...> %{
  ...>   "action" => "add",
  ...>   "file" => "stop_times.txt",
  ...>   "target" => "row"
  ...> }] |> diff_summary()
  %{
    "add" => [{{"stop_times.txt", "add", "row"}, 1}],
    "delete" => [
      {{"agency.txt", "delete", "file"}, 1},
      {{"calendar.txt", "delete", "column"}, 1},
    ]
  }
  """
  def diff_summary(diff) do
    order = %{"file" => 0, "column" => 1, "row" => 2}

    diff
    |> Enum.frequencies_by(fn r ->
      {Map.get(r, "file"), Map.get(r, "action"), Map.get(r, "target")}
    end)
    |> Enum.sort_by(fn {{_, _, target}, _} -> order |> Map.fetch!(target) end)
    |> Enum.group_by(fn {{_file, action, _target}, _n} -> action end)
  end

  def explanation_add_file(explanations, %{"action" => "add", "file" => file, "target" => "file"}) do
    [
      {file, dgettext("validations", ~s(A file named "%{file}" has been added), file: file)}
      | explanations
    ]
  end

  def explanation_add_file(explanations, _), do: explanations

  def explanation_delete_file(explanations, %{
        "action" => "delete",
        "file" => file,
        "target" => "file"
      }) do
    [{file, dgettext("validations", ~s(The file "%{file}" has been deleted), file: file)} | explanations]
  end

  def explanation_delete_file(explanations, _), do: explanations

  def explanation_update_stop_name(
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
        message: dgettext("validations", "Stop %{stop_id} has been renamed", stop_id: stop_id),
        before: initial_stop_name,
        after: new_stop_name,
        sort_key: initial_stop_name
      }
      | explanations
    ]
  end

  def explanation_update_stop_name(explanations, _) do
    explanations
  end

  def explanation_stop_wheelchair_access(
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
        message: dgettext("validations", "Wheelchair_boarding updated for stop %{stop_id}", stop_id: stop_id),
        before: initial_wheelchair_boarding,
        after: new_wheelchair_boarding,
        sort_key: stop_id
      }
      | explanations
    ]
  end

  def explanation_stop_wheelchair_access(explanations, _), do: explanations

  def explanation_update_stop_position(
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
    {lat1, _} = Float.parse(lat1)
    {lon1, _} = Float.parse(lon1)
    {lat2, _} = Float.parse(lat2)
    {lon2, _} = Float.parse(lon2)

    distance = round(curvilinear_abscissa({lat1, lon1}, {lat2, lon2}))

    if distance > 0 do
      [
        %{
          file: "stops.txt",
          type: "stop_position",
          message:
            dgettext("validations", "Stop %{stop_id} has been moved by %{distance}m",
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

  def explanation_update_stop_position(explanations, _), do: explanations

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
          message: dgettext("validations", "Color has been updated for route %{route_id}", route_id: route_id),
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
          message: dgettext("validations", "Text color has been updated for route %{route_id}", route_id: route_id),
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

  def explanation_route_short_name(
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
        message: dgettext("validations", "Route short name has been updated for route %{route_id}", route_id: route_id),
        before: initial_route_short_name,
        after: new_route_short_name,
        sort_key: route_id
      }
      | explanations
    ]
  end

  def explanation_route_short_name(explanations, _), do: explanations

  def explanation_route_long_name(
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
        message: dgettext("validations", "Route long name has been updated for route %{route_id}", route_id: route_id),
        before: initial_route_long_name,
        after: new_route_long_name,
        sort_key: route_id
      }
      | explanations
    ]
  end

  def explanation_route_long_name(explanations, _), do: explanations

  def explanation_route_type(
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
        message: dgettext("validations", "Route type has been updated for route %{route_id}", route_id: route_id),
        before: initial_route_type,
        after: new_route_type,
        sort_key: route_id
      }
      | explanations
    ]
  end

  def explanation_route_type(explanations, _), do: explanations

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
  """
  def curvilinear_abscissa({lat1, lon1}, {lat2, lon2}) do
    # Semi-major axis of WGS 84
    r = 6_378_137

    lat1r = deg2rad(lat1)
    lon1r = deg2rad(lon1)
    lat2r = deg2rad(lat2)
    lon2r = deg2rad(lon2)

    dlon = lon2r - lon1r

    r * :math.acos(:math.sin(lat1r) * :math.sin(lat2r) + :math.cos(lat1r) * :math.cos(lat2r) * :math.cos(dlon))
  end

  defp deg2rad(deg), do: deg * :math.pi() / 180.0

  def try_jason_decode(""), do: nil
  def try_jason_decode(input), do: Jason.decode!(input)
end
