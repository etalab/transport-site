defmodule TransportWeb.DatasetView do
  use TransportWeb, :view
  import TransportWeb.PaginationHelpers
  alias Transport.Dataset

  def render_sidebar_from_type(conn, dataset), do: render_panel_from_type(conn, dataset, "sidebar")

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

  def get_name(%{"organization" => organization}), do: organization["name"]
  def get_name(%{"owner" => owner}), do: owner["first_name"] <> " " <> owner["last_name"]

  def first_gtfs(dataset) do
    dataset
    |> Dataset.valid_gtfs()
    |> List.first()
  end
end
