defmodule TransportWeb.ValidationView do
  use TransportWeb, :view
  import Phoenix.Controller, only: [current_url: 1]

  import TransportWeb.ResourceView, only: [gtfs_template: 1]

  import TransportWeb.NeTExValidationReportComponent,
    only: [netex_validation_report: 1, netex_validation_report_title: 1]

  import Phoenix.Component, only: [live_render: 3, link: 1]

  def render("_" <> _ = partial, assigns) do
    render(TransportWeb.ResourceView, partial, assigns)
  end

  def has_errors?([]), do: false
  def has_errors?(summary) when is_list(summary), do: true

  def warning_label("lon_lat_inverted"),
    do: dgettext("validations", "Longitude and latitude coordinates inverted")

  def warning_label(warning) when is_binary(warning), do: warning
end
