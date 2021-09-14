defmodule Transport.DataVisualization do
  @moduledoc """
  Extract a geojson from a GTFS validation,
  in order to provide a data visualization of the validation issues
  """

  def has_features(nil), do: false
  def has_features(data_visualization), do: length(data_visualization["features"]) > 0

  @spec validation_data_vis(any) :: nil | map
  def validation_data_vis(nil), do: nil

  def validation_data_vis(validations) do
    validations
    |> Enum.map(fn {issue_type, issues} -> {issue_type, data_vis_per_issue_type(issues)} end)
    |> Enum.into(%{})
  end

  def data_vis_per_issue_type(issues) do
    severity = issues |> Enum.at(0) |> Map.get("severity")
    geojson = issues |> Enum.flat_map(fn issue -> issue["geojson"]["features"] end)

    %{
      "severity" => severity,
      "geojson" => %{"features" => geojson, "type" => "FeatureCollection"}
    }
  end
end
