defmodule TransportWeb.ResourceView do
  use TransportWeb, :view
  import TransportWeb.PaginationHelpers
  import Transport.Validation

  def format_related_objects(nil), do: ""
  def format_related_objects(related_objects) do
    related_objects
    |> Enum.map(fn %{"id" => id, "name" => name} -> content_tag(:li, "#{name} (#{id})") end)
  end

  def issue_type([]), do: nil
  def issue_type([h|_]), do: h["issue_type"]

  def template(issues) do
    %{
      "DuplicateStops" => "_duplicate_stops_issue.html",
      "ExtraFile" => "_extra_file_issue.html",
      "MissingFile" => "_missing_file_issue.html",
      "NullDuration" => "_speed_issue.html",
      "ExcessiveSpeed" => "_speed_issue.html",
      "NegativeTravelTime" => "_speed_issue.html",
      "Slow" => "_speed_issue.html",
      "UnusedStop" => "_unused_stop_issue.html",
      "InvalidCoordinates" => "_coordinates_issue.html",
      "MissingCoordinates" => "_coordinates_issue.html",
    }
    |> Map.get(issue_type(issues.entries), "_generic_issue.html")
  end
end
