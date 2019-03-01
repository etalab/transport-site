defmodule TransportWeb.DatasetView do
  use TransportWeb, :view
  alias Transport.Dataset
  alias TransportWeb.PaginationHelpers
  alias TransportWeb.Router.Helpers

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

  def pagination_links(%{path_info: ["datasets", "region", region]} = conn, datasets, _) do
    PaginationHelpers.pagination_links(
      conn,
      datasets,
      [region],
      path: &Helpers.dataset_path/4, action: :by_region
    )
  end
  def pagination_links(%{path_info: ["datasets", "aom", aom]} = conn, datasets, _) do
    PaginationHelpers.pagination_links(
      conn,
      datasets,
      [aom],
      path: &Helpers.dataset_path/4,
      action: :by_aom
    )
  end
  def pagination_links(conn, paginator, args) do
    PaginationHelpers.pagination_links(conn, paginator, args)
  end
end
