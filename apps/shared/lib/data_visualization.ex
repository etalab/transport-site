defmodule Transport.DataVisualization do
  @moduledoc """
  Build geojson data to visualize data validation alerts
  """
  require Logger

  @client HTTPoison
  @res HTTPoison.Response
  @timeout 180_000

  @doc """
  Try to convert a GTFS structure into GeoJson.
  The GTFS may be a file path or data.
  """
  @spec convert_to_geojson(binary()) :: binary()
  def convert_to_geojson(nil), do: nil

  def convert_to_geojson(file_path_or_content),
    do:
      file_path_or_content
      |> dertermine_content_type()
      |> build_http_body(file_path_or_content)
      |> post_http_request()
      |> handle_response()

  def has_features(nil), do: false
  def has_features(data_visualization), do: length(data_visualization["features"]) > 0

  defp gtfs_to_json_converter_url, do: Application.fetch_env!(:transport, :gtfs_to_json_converter_url)

  defp handle_response({:ok, %@res{status_code: 200, body: geojson_encoded}}), do: geojson_encoded

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
        gtfs_to_json_converter_url(),
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

  # create  the data_vis from the validation output only
  # when we get rid of validation_data_vis(geojson_encoded, validations)
  # we will simply this
  def validation_data_vis(validations) do
    data_vis_content(validations)
  end

  def data_vis_content(validations) do
    validations
    |> Enum.map(fn {issue_type, issues} -> {issue_type, data_vis_per_issue_type(issues)} end)
    |> Enum.into(%{})
  end

  def data_vis_per_issue_type(issues) do
    severity = issues |> Enum.at(0) |> Map.get("severity")
    geojson = issues |> Enum.flat_map(fn issue -> issue["geojson"]["features"] end)
    %{"severity" => severity, "geojson" => %{"features" => geojson, "type" => "FeatureCollection"}}
  end
end
