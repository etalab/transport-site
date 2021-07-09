defmodule Transport.DataVisualisation do
  @moduledoc """
  Build geojson data to visualize data validation alerts
  """

  @client HTTPoison
  @res HTTPoison.Response
  @timeout 180_000

  @geojson_converter_url "https://convertisseur.transport.data.gouv.fr/gtfs2geojson_sync"


  @spec convert_to_geojson(binary()) :: binary()
  def convert_to_geojson(file_path) do
    geojson_converter_response =
      @client.post(
        @geojson_converter_url,
        {:multipart, [{:file, file_path}]},
        [{"content-type", "multipart/form-data;"}],
        recv_timeout: @timeout
      )

    case geojson_converter_response do
      {:ok, %@res{status_code: 200, body: geojson_encoded}} -> geojson_encoded
      _ -> nil
    end
  end

  @spec validation_data_vis(any, any) :: nil | map
  def validation_data_vis(nil, _), do: nil

  def validation_data_vis(geojson_encoded, validations) do
    case Jason.decode(geojson_encoded) do
      {:ok, geojson} ->
        data_vis_content(geojson, validations)

      _ ->
        %{}
    end
  end

  defp data_vis_content(geojson, validations) do
    validations
    |> Map.new(fn {issue_name, issues_list} ->
      issues_map = get_issues_map(issues_list)

      # create a map with with stop id as keys and geojson features as values
      features_map =
        geojson["features"]
        |> Map.new(fn feature -> {feature["properties"]["id"], feature} end)

      issues_geojson = get_issues_geojson(geojson, issues_map, features_map)

      severity = issues_map |> Map.values() |> Enum.at(0) |> Map.get("severity")
      # severity is used to customize the markers color in leaflet
      {issue_name, %{"severity" => severity, "geojson" => issues_geojson}}
    end)
  end

  defp get_issues_map(issues_list) do
    # create a map with stops id as keys and issue description as values
    Map.new(issues_list, fn issue ->
      simplified_issue = simplified_issue(issue)

      {issue["object_id"], simplified_issue}
    end)
  end

  defp simplified_issue(issue) do
    # keep only on related stop in related objects
    issue
    |> Map.update("related_objects", [], fn related_objects ->
      related_objects |> Enum.filter(fn o -> o["object_type"] == "Stop" end) |> List.first()
    end)
  end

  defp get_issues_geojson(geojson, issues_map, features_map) do
    # create a geojson for each issue type
    Map.update(geojson, "features", [], fn _features ->
      issues_map
      |> Enum.flat_map(fn {id, issue} ->
        features_from_issue(issue, id, features_map)
      end)
    end)
  end

  defp features_from_issue(issue, id, features_map) do
    # features contains a list of stops, related_stops and Linestrings
    # Linestrings are used to link a stop and its related stop

    case features_map[id] do
      nil ->
        []

      feature ->
        properties = Map.put(feature["properties"] || %{}, "details", Map.get(issue, "details"))
        stop = Map.put(feature, "properties", properties)

        case issue["related_objects"] do
          %{"id" => id, "name" => _name} ->
            related_stop = features_map[id]

            stops_link = %{
              "type" => "Feature",
              "properties" => %{
                "details" => Map.get(issue, "details")
              },
              "geometry" => %{
                "type" => "LineString",
                "coordinates" => [
                  stop["geometry"]["coordinates"],
                  related_stop["geometry"]["coordinates"]
                ]
              }
            }

            [stop, related_stop, stops_link]

          _ ->
            [stop]
        end
    end
  end
end
