defmodule TransportWeb.StatsController do
  use TransportWeb, :controller

  @spec index(Plug.Conn.t(), any) :: Plug.Conn.t()
  def index(conn, _params) do
    stats = Transport.StatsHandler.compute_stats()

    conn
    |> assign(:nb_datasets, stats.nb_datasets)
    |> assign(:nb_pt_datasets, stats.nb_pt_datasets)
    |> assign(:nb_aoms, stats.nb_aoms)
    |> assign(:nb_aoms_with_data, stats.nb_aoms_with_data)
    |> assign(:nb_regions, stats.nb_regions)
    |> assign(:nb_regions_completed, stats.nb_regions_completed)
    |> assign(:population_totale, stats.population_totale)
    |> assign(:population_couverte, stats.population_couverte)
    |> assign(:ratio_aom_with_at_most_warnings, stats.ratio_aom_with_at_most_warnings)
    |> assign(:ratio_aom_good_quality, stats.ratio_aom_good_quality)
    |> assign(:aom_with_errors, stats.aom_with_errors)
    |> assign(:aom_with_fatal, stats.aom_with_fatal)
    |> assign(:nb_official_public_transit_realtime, stats.nb_official_public_transit_realtime)
    |> assign(:nb_unofficial_public_transit_realtime, stats.nb_unofficial_public_transit_realtime)
    |> assign(:nb_reusers, stats.nb_reusers)
    |> assign(:nb_reuses, stats.nb_reuses)
    |> assign(:nb_dataset_types, stats.nb_dataset_types)
    |> assign(:nb_gtfs, stats.nb_gtfs)
    |> assign(:nb_netex, stats.nb_netex)
    |> assign(:nb_bss_datasets, stats.nb_bss_datasets)
    |> assign(:nb_bikes_datasets, stats.nb_bikes_datasets)
    |> assign(:droms, ["antilles", "guyane", "mayotte", "reunion"])
    |> render("index.html")
  end
end
