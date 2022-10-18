defmodule TransportWeb.API.GeoQueryController do
  use TransportWeb, :controller
  import Ecto.Query

  def index(%Plug.Conn{} = conn, %{"data" => slug}) do
    if Map.has_key?(config(), slug) do
      transport_publisher_label = Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)
      %{dataset_type: dataset_type, transform_fn: transform_fn} = Map.fetch!(config(), slug)

      get_geojson = fn ->
        DB.Dataset
        |> DB.Repo.get_by!(type: dataset_type, organization: transport_publisher_label)
        |> Map.fetch!(:id)
        |> DB.GeoDataImport.dataset_latest_geo_data_import()
        |> transform_fn.()
      end

      geojson = Transport.Cache.API.fetch("#{slug}_data", get_geojson, :timer.hours(1))
      conn |> json(geojson)
    else
      render_404(conn)
    end
  end

  def index(%Plug.Conn{} = conn, _), do: render_404(conn)

  def render_404(%Plug.Conn{} = conn), do: conn |> put_status(404) |> json(%{"message" => "Not found"})

  defp config do
    %{
      "bnlc" => %{dataset_type: "carpooling-areas", transform_fn: &bnlc_geojson/1},
      "parkings-relais" => %{dataset_type: "private-parking", transform_fn: &parkings_relais_geojson/1}
    }
  end

  def bnlc_geojson(%DB.GeoDataImport{} = geo_data_import) do
    add_fields = fn query -> from(g in query, select_merge: %{nom_lieu: fragment("payload->>'nom_lieu'")}) end
    DB.GeoData.geo_data_as_geojson(geo_data_import, add_fields)
  end

  def parkings_relais_geojson(%DB.GeoDataImport{} = geo_data_import) do
    add_fields = fn query ->
      from(g in query,
        select_merge: %{nom: fragment("payload->>'nom'"), nb_pr: fragment("(payload->>'nb_pr')::int")}
      )
    end

    DB.GeoData.geo_data_as_geojson(geo_data_import, add_fields)
  end
end
