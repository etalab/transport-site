defmodule TransportWeb.ResourceView do
  use TransportWeb, :view
  import TransportWeb.PaginationHelpers
  import DB.Validation
  import Phoenix.Controller, only: [current_url: 2]

  def format_related_objects(nil), do: ""
  def format_related_objects(related_objects) do
    for %{"id" => id, "name" => name} <- related_objects, do: content_tag(:li, "#{name} (#{id})")
  end

  def issue_type([]), do: nil
  def issue_type([h|_]), do: h["issue_type"]

  def template(issues) do
    Map.get(
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
      },
      issue_type(issues.entries),
      "_generic_issue.html"
    )
  end

  @spec action_path(Plug.Conn.t()) :: any
  def action_path(%Plug.Conn{params: %{"resource_id" => r_id} = params} = conn), do:
    resource_path(conn, :post_file, params["dataset_id"], r_id)
  def action_path(%Plug.Conn{params: params} = conn), do:
    resource_path(conn, :post_file, params["dataset_id"])

  def title(%Plug.Conn{params: %{"resource_id" => _}}), do: "Modify a resource" #dgettext("resource", "Modifiy resource")
  def title(_), do: "Add a resource" #dgettext("resource", "Add a resource")

  def remote?(%{"filetype" => "remote"}), do: true
  def remote?(_), do: false
end
