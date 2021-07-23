defmodule Transport.DataVisualization do
  @moduledoc """
  Build geojson data to visualize data validation alerts
  """
  require Logger

  @client HTTPoison
  @res HTTPoison.Response
  @timeout 180_000

  @geojson_converter_url "https://convertisseur.transport.data.gouv.fr/gtfs2geojson_sync"

  @doc """
  Try to convert a GTFS structure into GeoJson.
  The GTFS may be a file path or data.
  """
  @spec convert_to_geojson(binary()) :: binary()
  def convert_to_geojson(file_path_or_content),
    do:
      dertermine_content_type(file_path_or_content)
      |> IO.inspect()
      |> build_http_body(file_path_or_content)
      |> post_http_request()
      |> handle_response()
      |> IO.inspect()

  def has_features(nil), do: false
  def has_features(data_visualization), do: length(data_visualization["features"]) > 0

  defp handle_response({:ok, %@res{status_code: 200, body: geojson_encoded}}), do: geojson_encoded # |> Jason.decode!()

  defp handle_response({:ok, %@res{status_code: 500, body: body}}) do
    Logger.warn("Error during geojson conversion : #{body}")
    nil
  end

  defp handle_response({:error, %HTTPoison.Error{reason: reason}}) do
    Logger.error("Technical error during geojson conversion : #{reason}")
    nil
  end

  defp post_http_request(body),
    do:
      @client.post(
        @geojson_converter_url,
        body,
        [{"content-type", "multipart/form-data;"}],
        recv_timeout: @timeout
      )

  defp dertermine_content_type(file_path_or_content) do
    case File.exists?(file_path_or_content) do
      true -> :file_path
      _ -> :content
    end
  end

  defp build_http_body(:content, file_path_or_content),
    do: {
      :multipart,
      [
        {"file", file_path_or_content, {"form-data", [name: "file", filename: "gtfs.zip"]}, []}
      ]
    }

  defp build_http_body(:file_path, file_path_or_content),
    do: {
      :multipart,
      [{:file, file_path_or_content}]
    }

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
