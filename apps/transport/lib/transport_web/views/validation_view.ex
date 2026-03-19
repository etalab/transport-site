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
      netex_validation_report_title: 1,
      to_netex_validation_report: 1
    ]

  import TransportWeb.PaginationHelpers

  def render("_" <> _ = partial, assigns) do
    render(TransportWeb.ResourceView, partial, assigns)
  end

  def has_errors?([]), do: false
  def has_errors?(summary) when is_list(summary), do: true

  def netex_pagination_links(conn, issues, validation_id, current_category) do
    pagination_links(conn, issues, [validation_id],
      issues_category: current_category,
      token: conn.params["token"],
      path: &netex_issues_path/4,
      action: :show
    )
  end

  defp netex_issues_path(conn, action, validation_id, params) do
    validation_path(conn, action, validation_id, params) |> to_netex_validation_report()
  end
end
