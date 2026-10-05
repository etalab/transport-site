defmodule TransportWeb.ValidationView do
  use TransportWeb, :view
  import Phoenix.Controller, only: [current_url: 1]

  import TransportWeb.ResourceView,
    only: [
      gtfs_template: 1,
      netex_template: 0
    ]

  import TransportWeb.NeTExReportComponents,
    only: [
      netex_validation_report_content: 1,
      netex_validation_report_title: 1
    ]

  import Phoenix.Component, only: [sigil_H: 2, live_render: 3]

  def render("_" <> _ = partial, assigns) do
    render(TransportWeb.ResourceView, partial, assigns)
  end

  def has_errors?([]), do: false
  def has_errors?(summary) when is_list(summary), do: true

  def warning_label("lon_lat_inverted"),
    do: dgettext("validations", "Longitude and latitude coordinates inverted")

  def warning_label(warning) when is_binary(warning), do: warning

  def netex_pagination_links(conn, issues, current_category) do
    assigns = %{conn: conn, issues: issues, current_category: current_category}

    ~H"""
    <.pagination conn={@conn} page={@issues} params={[issues_category: @current_category]} anchor="validation-report" />
    """
  end
end
