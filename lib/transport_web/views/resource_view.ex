defmodule TransportWeb.ResourceView do
  use TransportWeb, :view
  import TransportWeb.PaginationHelpers
  import Transport.Validation

  def format_related_objects(nil), do: ""
  def format_related_objects(related_objects) do
    related_objects
    |> Enum.map(fn %{"id" => id, "name" => name} -> "#{name} (#{id})" end)
    |> Enum.join(", ")
  end

  def issue_type([]), do: nil
  def issue_type([h|_]), do: h["issue_type"]

  def template(issues) do
    case issue_type(issues.entries) do
      "DuplicateStops" -> "_duplicate_stops_issue.html"
      _ -> "_generic_issue.html"
    end
  end
end
