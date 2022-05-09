defmodule Transport.DataVisualization do
  @moduledoc """
  Wrapper for DataVisualization
  """
  @callback has_features(map() | nil) :: boolean()
  @callback validation_data_vis(any) :: nil | map

  defp impl, do: Application.get_env(:transport, :data_visualization)
  def has_features(validations), do: impl().has_features(validations)
  def validation_data_vis(validations), do: impl().validation_data_vis(validations)
end

defmodule Transport.DataVisualization.Impl do
  @moduledoc """
  Extract a geojson from a GTFS validation,
  in order to provide a data visualization of the validation issues
  """
  @behaviour Transport.DataVisualization

  @impl Transport.DataVisualization
  def has_features(nil), do: false
  def has_features(data_visualization), do: length(data_visualization["features"]) > 0

  @impl Transport.DataVisualization
  @spec validation_data_vis(any) :: nil | map
  def validation_data_vis(nil), do: nil

  def validation_data_vis(validations) do
    validations
    |> Enum.map(fn {issue_type, issues} -> {issue_type, data_vis_per_issue_type(issues)} end)
    |> Enum.into(%{})
  end

  defp data_vis_per_issue_type(issues) do
    severity = issues |> Enum.at(0) |> Map.get("severity")

    geojson =
      issues
      |> Enum.flat_map(fn issue -> get_in(issue, ["geojson", "features"]) || [] end)
      |> Enum.reject(&is_nil(&1))

    %{
      "severity" => severity,
      "geojson" => %{"features" => geojson, "type" => "FeatureCollection"}
    }
  end
end
