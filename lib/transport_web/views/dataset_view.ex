defmodule TransportWeb.DatasetView do
  use TransportWeb, :view
  import TransportWeb.PaginationHelpers
  alias Transport.Dataset

  def render_sidebar_from_type(conn, dataset), do: render_panel_from_type(conn, dataset, "sidebar")
  def render_description_from_type(conn, dataset), do: render_panel_from_type(conn, dataset, "description")

  def render_panel_from_type(conn, dataset, panel_type) do
    render_existing(
      TransportWeb.DatasetView,
      "_#{panel_type}_#{dataset.type}.html",
      dataset: dataset,
      conn: conn
    )
  end

  def format_date(date) do
    date
    |> Timex.parse!("{ISO:Extended}")
    |> Timex.format!("{0D}/{0M}/{YYYY} à {h24}h{0m}")
  end
end
