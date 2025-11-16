defmodule TransportWeb.API.StatsController do
  use TransportWeb, :controller
  import Ecto.Query
  alias Geo.JSON
  alias OpenApiSpex.Operation

  @spec open_api_operation(any) :: Operation.t()
  def open_api_operation(action), do: apply(__MODULE__, :"#{action}_operation", [])

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

  @spec vehicles_sharing_operation() :: Operation.t()
  def vehicles_sharing_operation,
    do: %Operation{
      tags: ["stats"],
      summary: "Show vehicles sharing stats",
      description: "Show vehicles sharing stats",
      operationId: "API.StatsController.vehicles_sharing",
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

  @spec geojson([map()]) :: map()
  def geojson(features),
    do: %{
      "type" => "FeatureCollection",
      # This is now completely incorrect!
      "name" => "Autorités organisatrices de Mobiltés",
      "features" => features
    }

  @spec filter_neg(nil | integer()) :: nil | non_neg_integer()
  defp filter_neg(nil), do: nil
  defp filter_neg(val) when val < 0, do: nil
  defp filter_neg(val) when val >= 0, do: val

  @spec features([map()]) :: [map()]
  def features(result) do
    result
    |> Enum.map(fn aom ->
      %{
        "geometry" => aom.geometry |> JSON.encode!(),
        "type" => "Feature",
        "properties" => %{
          "nom" => Map.get(aom, :nom, ""),
          "insee" => Map.get(aom, :insee),
          "quality" => %{
            "expired_from" => %{
              # negative values are up to date datasets, we filter them
              "nb_days" => aom |> Map.get(:quality, %{}) |> Map.get(:expired_from) |> filter_neg,
              "status" =>
                case aom |> Map.get(:quality, %{}) |> Map.get(:expired_from) do
                  # if no validity period has been found, it's either that there was no data
                  # or that we were not able to read them
                  nil -> "no_data"
                  i when i > 0 -> "outdated"
                  _ -> "up_to_date"
                end
            },
            "error_level" => aom |> Map.get(:quality, %{}) |> Map.get(:error_level)
          }
        }
      }
    end)
    |> Enum.to_list()
  end

  @spec vehicles_sharing_features([map()]) :: [map()]
  def vehicles_sharing_features(result) do
    result
    |> Enum.reject(fn r -> is_nil(r.geometry) end)
    |> Enum.map(fn r ->
      %{
        "geometry" => r.geometry |> JSON.encode!(),
        "type" => "Feature",
        "properties" => Map.take(r, Enum.filter(Map.keys(r), fn k -> to_string(k) != "geometry" end))
      }
    end)
  end

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%Plug.Conn{} = conn, _params), do: render_features(conn, :aoms, "api-stats-aoms")

  @spec vehicles_sharing(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def vehicles_sharing(%Plug.Conn{} = conn, _params),
    do: render_features(conn, :vehicles_sharing)

  @spec quality(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def quality(%Plug.Conn{} = conn, _params), do: render_features(conn, :quality, "api-stats-quality")

  #
  # (not using @doc because this is a private method and it would then generate a warning ;
  # this is a sign the whole computation should move to a separate module when we can!)
  #
  # This method is the central computation point for GeoJSON features.
  #
  # Because the passed `query` can be costly to compute, this method supports optional
  # caching via `Transport.Cache` (enabled only if a `cache_key` is provided).
  #
  # Since the data structures are rich (many key/values), the computation result is cached
  # *after* encoding it to JSON, which is many time (100x during our tests) faster than
  # storing the original data structure in cache then re-encoding at each request.
  #
  # Because `render` does not support passing a rendered JSON (as binary) today, and to avoid
  # resorting to `send_resp` directly, we leverage `Transport.Shared.ConditionalJSONEncoder` to
  # skip JSON encoding, signaling the need to do so via a {:skip_json_encoding, data} tuple.
  #
  @spec render_features(Plug.Conn.t(), atom(), binary()) :: Plug.Conn.t()
  defp render_features(conn, item, cache_key) do
    data =
      Transport.Cache.fetch(cache_key, fn -> rendered_geojson(item) end, Transport.PreemptiveStatsCache.cache_ttl())

    render(conn, data: {:skip_json_encoding, data})
  end

  @spec render_features(Plug.Conn.t(), atom()) :: Plug.Conn.t()
  defp render_features(conn, item) do
    data = rendered_geojson(item)
    render(conn, data: {:skip_json_encoding, data})
  end

  def rendered_geojson(item, ecto_opts \\ [])

  def rendered_geojson(:quality, ecto_opts) do
    quality_features_query()
    |> DB.Repo.all(ecto_opts)
    |> features()
    |> geojson()
    |> Jason.encode!()
  end

  def rendered_geojson(:aoms, ecto_opts) do
    aom_features_query()
    |> DB.Repo.all(ecto_opts)
    |> vehicles_sharing_features()
    |> geojson()
    |> Jason.encode!()
  end

  def rendered_geojson(:vehicles_sharing, ecto_opts) do
    vehicles_sharing_features_query()
    |> DB.Repo.all(ecto_opts)
    |> vehicles_sharing_features()
    |> geojson()
    |> Jason.encode!()
  end

  @spec aom_features_query :: Ecto.Query.t()
  defp aom_features_query do
    DB.DatasetGeographicView
    |> join(:inner, [gv], dataset in DB.Dataset, on: dataset.id == gv.dataset_id, as: :dataset)
    |> join(:inner, [dataset: d], a in assoc(d, :declarative_spatial_areas), as: :administrative_division)
    |> join(:inner, [dataset: d], r in assoc(d, :resources), as: :resource)
    |> select([gv, dataset, administrative_division: ad, resource: r], %{
      geometry: gv.geom,
      nb: count(gv.dataset_id, :distinct),
      nom: fragment("string_agg(distinct ?, ', ')", ad.nom),
      insee: min(ad.insee),
      gtfs: fragment("sum(case when ? = 'GTFS' then 1 else 0 end)", r.format),
      netex: fragment("sum(case when ? = 'NeTEx' then 1 else 0 end)", r.format),
      gtfs_rt: fragment("sum(case when ? = 'gtfs-rt' then 1 else 0 end)", r.format),
      siri: fragment("sum(case when ? = 'SIRI' then 1 else 0 end)", r.format),
      siri_lite: fragment("sum(case when ? = 'SIRI Lite' then 1 else 0 end)", r.format)
    })
    |> where(
      [_gv, dataset],
      dataset.type == "public-transit" and dataset.is_active and dataset.id in subquery(relevant_coverage_datasets())
    )
    |> group_by([gv], gv.geom)
  end

  @spec vehicles_sharing_features_query :: Ecto.Query.t()
  def vehicles_sharing_features_query do
    DB.DatasetGeographicView
    |> join(:left, [gv], dataset in DB.Dataset, on: dataset.id == gv.dataset_id)
    |> select([gv, dataset], %{
      geometry: fragment("geom as geometry"),
      names: fragment("array_agg(? order by ? asc)", dataset.custom_title, dataset.custom_title),
      slugs: fragment("array_agg(? order by ? asc)", dataset.slug, dataset.custom_title)
    })
    |> where(
      [_gv, dataset],
      dataset.type == "vehicles-sharing" and dataset.is_active and dataset.id in subquery(relevant_coverage_datasets())
    )
    |> group_by(fragment("geometry"))
  end

  @spec quality_features_query :: Ecto.Query.t()
  def quality_features_query do
    dt = Date.utc_today() |> Date.to_iso8601()

    error_info_sub = dataset_error_levels()
    expired_info_sub = dataset_expiration_dates()

    DB.DatasetGeographicView
    |> join(:inner, [gv], dataset in DB.Dataset, on: dataset.id == gv.dataset_id, as: :dataset)
    |> join(:inner, [dataset: d], a in assoc(d, :declarative_spatial_areas), as: :administrative_division)
    |> join(:left, [dataset: d], error_info in subquery(error_info_sub),
      on: error_info.dataset_id == d.id,
      as: :error_info
    )
    |> join(:left, [dataset: d], expired_info in subquery(expired_info_sub),
      on: expired_info.dataset_id == d.id,
      as: :expired_info
    )
    |> where(
      [dataset: d],
      d.type == "public-transit" and d.is_active and d.id in subquery(relevant_coverage_datasets())
    )
    |> select(
      [gv, administrative_division: ad, error_info: error_info, expired_info: expired_info],
      %{
        geometry: gv.geom,
        insee: min(ad.insee),
        nom: fragment("string_agg(distinct ?, ', ')", ad.nom),
        quality: %{
          expired_from: fragment("TO_DATE(?, 'YYYY-MM-DD') - max(?)", ^dt, expired_info.end_date),
          error_level: fragment("case max(CASE max_error::text
              WHEN 'Fatal' THEN 1
              WHEN 'Error' THEN 2
              WHEN 'Warning' THEN 3
              WHEN 'Information' THEN 4
              WHEN 'NoError' THEN 5
              END)
            WHEN 1 THEN 'Fatal'
            WHEN 2 THEN 'Error'
            WHEN 3 THEN 'Warning'
            WHEN 4 THEN 'Information'
            WHEN 5 THEN 'NoError'
          END
          ")
        }
      }
    )
    |> group_by([gv], gv.geom)
  end

  def dataset_expiration_dates do
    DB.Dataset.base_query()
    |> DB.Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
    |> where([resource: r], r.is_available == true)
    |> select([dataset: d, metadata: m], %{
      dataset_id: d.id,
      end_date: fragment("TO_DATE(?->>'end_date', 'YYYY-MM-DD')", m.metadata)
    })
  end

  def dataset_error_levels do
    DB.Dataset.base_query()
    |> DB.Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
    |> DB.ResourceMetadata.where_gtfs_up_to_date()
    |> where([resource: r], r.is_available == true)
    |> select([dataset: d, multi_validation: mv], %{dataset_id: d.id, max_error: mv.max_error})
  end

  def relevant_coverage_datasets do
    DB.Dataset.base_query()
    |> join(:inner, [dataset: d], a in assoc(d, :declarative_spatial_areas), as: :administrative_division)
    # Covering a commune, EPCI OR the Ile-de-France region
    |> where([administrative_division: ad], ad.type in [:commune, :epci] or (ad.type == :region and ad.insee == "11"))
    |> distinct(true)
    |> select([dataset: d], d.id)
  end
end
