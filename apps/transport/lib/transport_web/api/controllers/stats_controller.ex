defmodule TransportWeb.API.StatsController do
  use TransportWeb, :controller
  alias OpenApiSpex.Operation

  @spec open_api_operation(any) :: Operation.t()
  def open_api_operation(action), do: apply(__MODULE__, :"#{action}_operation", [])

  @spec regions_operation() :: Operation.t()
  def regions_operation,
    do: %Operation{
      tags: ["stats"],
      summary: "Show regions",
      description: "Show covered french administrative regions",
      operationId: "API.StatsController.regions",
      parameters: [],
      responses: %{
        200 => Operation.response("GeoJSON", "application/json", TransportWeb.API.Schemas.GeoJSONResponse)
      }
    }

  @spec index_operation() :: Operation.t()
  def index_operation,
    do: %Operation{
      tags: ["stats"],
      summary: "Show regions",
      description: "Show covered french administrative regions",
      operationId: "API.StatsController.index",
      parameters: [],
      responses: %{
        200 => Operation.response("GeoJSON", "application/json", TransportWeb.API.Schemas.GeoJSONResponse)
      }
    }

  @spec bike_scooter_sharing_operation() :: Operation.t()
  def bike_scooter_sharing_operation,
    do: %Operation{
      tags: ["stats"],
      summary: "Show bike and scooter sharing stats",
      description: "Show bike and scooter sharing stats",
      operationId: "API.StatsController.bike_scooter_sharing",
      parameters: [],
      responses: %{
        200 => Operation.response("GeoJSON", "application/json", TransportWeb.API.Schemas.GeoJSONResponse)
      }
    }

  @spec quality_operation() :: Operation.t()
  def quality_operation,
    do: %Operation{
      tags: ["stats"],
      summary: "Show data quality stats",
      description: "Show data quality stats",
      operationId: "API.StatsController.quality",
      parameters: [],
      responses: %{
        200 => Operation.response("GeoJSON", "application/json", TransportWeb.API.Schemas.GeoJSONResponse)
      }
    }

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%Plug.Conn{} = conn, _params),
    do: render_features(conn, Transport.StatsHandler.aom_features_query(), "api-stats-aoms")

  @spec regions(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def regions(%Plug.Conn{} = conn, _params),
    do: render_features(conn, Transport.StatsHandler.region_features_query(), "api-stats-regions")

  @spec bike_scooter_sharing(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def bike_scooter_sharing(%Plug.Conn{} = conn, _params),
    do: render_features(conn, Transport.StatsHandler.bike_scooter_sharing_rendered_geojson())

  @spec quality(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def quality(%Plug.Conn{} = conn, _params),
    do: render_features(conn, Transport.StatsHandler.quality_features_query(), "api-stats-quality")

  # Because the passed `query` can be costly to compute, this method supports optional
  # caching via `Transport.Cache` (enabled only if a `cache_key` is provided).
  # As of January 2025, the bike scooter sharing stats are not cached, the rest are.
  #
  # Since the data structures are rich (many key/values), the computation result is cached
  # *after* encoding it to JSON, which is many time (100x during our tests) faster than
  # storing the original data structure in cache then re-encoding at each request.
  #
  # Because `render` does not support passing a rendered JSON (as binary) today, and to avoid
  # resorting to `send_resp` directly, we leverage `Transport.Shared.ConditionalJSONEncoder` to
  # skip JSON encoding, signaling the need to do so via a {:skip_json_encoding, data} tuple.
  @spec render_features(Plug.Conn.t(), Ecto.Query.t(), binary()) :: Plug.Conn.t()
  defp render_features(conn, query, cache_key) do
    comp_fn = fn ->
      Transport.StatsHandler.query_to_rendered_geojson(query)
    end

    rendered_geojson = Transport.Cache.fetch(cache_key, comp_fn)

    render(conn, data: {:skip_json_encoding, rendered_geojson})
  end

  defp render_features(conn, rendered_geojson) do
    render(conn, data: {:skip_json_encoding, rendered_geojson})
  end
end
