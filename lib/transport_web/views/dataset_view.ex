defmodule TransportWeb.DatasetView do
  use TransportWeb, :view
  alias Transport.Dataset
  alias TransportWeb.PaginationHelpers
  alias TransportWeb.Router.Helpers
  import Phoenix.Controller, only: [current_url: 2]

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

  def pagination_links(%{path_info: ["datasets", "region", region]} = conn, datasets) do
    kwargs = [path: &Helpers.dataset_path/4, action: :by_region] |> add_order_by(conn.params)

    PaginationHelpers.pagination_links(
      conn,
      datasets,
      [region],
      kwargs
    )
  end
  def pagination_links(%{path_info: ["datasets", "aom", aom]} = conn, datasets) do
    kwargs = [path: &Helpers.dataset_path/4, action: :by_aom] |> add_order_by(conn.params)

    PaginationHelpers.pagination_links(
      conn,
      datasets,
      [aom],
      kwargs
    )
  end
  def pagination_links(conn, paginator) do
    PaginationHelpers.pagination_links(conn, paginator)
  end

  def order_link(conn, order_by) do
    msg = %{
      "alpha" => dgettext("page-shortlist", "Alphabetical"),
      "most_recent" => dgettext("page-shortlist", "Most recent")
    }[order_by]

    case conn.assigns do
      %{order_by: ^order_by} -> ~E"<span class=\"activefilter\"><%= msg %></span>"
      _ -> link(msg, to: current_url(conn, Map.put(conn.params, "order_by", order_by)))
    end
  end

  defp add_order_by(kwargs, %{"order_by" => order}), do: Keyword.put(kwargs, :order_by, order)
  defp add_order_by(kwargs, _), do: kwargs
end
