defmodule TransportWeb.ExploreController do
  use TransportWeb, :controller

  def index(conn, _params) do
    consolidated_datasets_assigns =
      Transport.ConsolidatedDataset.geo_data_datasets()
      |> Map.new(&{String.to_atom("#{&1}_dataset"), Transport.ConsolidatedDataset.dataset(&1)})

    conn
    |> merge_assigns(consolidated_datasets_assigns)
    |> render("explore.html")
  end

  def vehicle_positions(conn, _params) do
    conn |> redirect(to: explore_path(conn, :index))
  end

  defp national_map_disabled?, do: Application.fetch_env!(:transport, :disable_national_gtfs_map)

  def gtfs_stops(conn, _params) do
    if national_map_disabled?() do
      conn
      |> put_status(:not_found)
      |> put_view(ErrorView)
      |> assign(:custom_message, dgettext("errors", "Feature temporarily disabled"))
      |> render("503.html")
    else
      conn
      |> assign(:page_title, dgettext("explore", "Consolidated GTFS stops map"))
      |> render("gtfs_stops.html")
    end
  end
end
