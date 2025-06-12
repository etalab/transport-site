defmodule TransportWeb.API.StatsController do
  use TransportWeb, :controller
  alias DB.{AOM, Dataset, DatasetGeographicView, Region, Repo}
  import Ecto.Query
  alias Geo.JSON
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

  def new_aom_without_datasets?(%{created_after_2021: true, nb_datasets: 0}), do: true
  def new_aom_without_datasets?(%{created_after_2021: true, dataset_types: %{pt: 0}}), do: true
  def new_aom_without_datasets?(_), do: false

  @spec features([map()]) :: [map()]
  def features(result) do
    result
    |> Enum.reject(fn aom -> is_nil(aom.geometry) or new_aom_without_datasets?(aom) end)
    |> Enum.map(fn aom ->
      dataset_types =
        aom
        |> Map.get(:dataset_types, [])
        |> Enum.filter(fn {_, v} -> !is_nil(v) end)
        |> Enum.into(%{})

      %{
        "geometry" => aom.geometry |> JSON.encode!(),
        "type" => "Feature",
        "properties" => %{
          "dataset_count" => Map.get(aom, :nb_datasets, 0),
          "completed" => Map.get(aom, :is_completed, false),
          "nom" => Map.get(aom, :nom, ""),
          "id" => aom.id,
          "forme_juridique" => Map.get(aom, :forme_juridique, ""),
          "nb_other_datasets" => Map.get(aom, :nb_other_datasets, 0),
          "quality" => %{
            "expired_from" => %{
              # negative values are up to date datasets, we filter them
              "nb_days" => aom |> Map.get(:quality, %{}) |> Map.get(:expired_from) |> filter_neg,
              "status" =>
                case aom |> Map.get(:quality, %{}) |> Map.get(:expired_from) do
                  # if no validity period has been found, it's either that there was no data
                  # or that we were not able to read them
                  nil ->
                    case dataset_types[:pt] do
                      0 -> "no_data"
                      _ -> "unreadable"
                    end

                  i when i > 0 ->
                    "outdated"

                  _ ->
                    "up_to_date"
                end
            },
            "error_level" => aom |> Map.get(:quality, %{}) |> Map.get(:error_level)
          },
          "dataset_formats" =>
            aom
            |> Map.get(:dataset_formats, [])
            |> Enum.filter(fn {_, v} -> v != nil end)
            |> Enum.into(%{}),
          "dataset_types" => dataset_types
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
        # NOTE: there is a bug here - the key is an atom.
        # I won't change it now because it would mean more changes somewhere else, maybe.
        # `Map.reject(fn({k,v}) -> k == :geometry end)` will do it.
        "properties" => Map.take(r, Enum.filter(Map.keys(r), fn k -> k != "geometry" end))
      }
    end)
  end

  defmacro count_aom_types(aom_id, type, include_aggregates: true) do
    quote do
      fragment(
        """
        select count(d.id)
        from dataset d
        left join dataset_aom_legal_owner a on a.dataset_id = d.id and a.aom_id = ?
        where (d.aom_id = ? or a.dataset_id is not null) and d.is_active and d.type = ?
        """,
        unquote(aom_id),
        unquote(aom_id),
        unquote(type)
      )
    end
  end

  defmacro count_aom_types(aom_id, type) do
    quote do
      fragment(
        """
        select count(d.id)
        from dataset d
        where d.aom_id = ? and d.is_active and d.type = ?
        """,
        unquote(aom_id),
        unquote(type)
      )
    end
  end

  defmacro count_aom_format(aom_id, format) do
    quote do
      fragment(
        """
        SELECT COUNT(format)
        FROM resource
        WHERE format = ?
        AND dataset_id in (
          select d.id
          from dataset d
          left join dataset_aom_legal_owner a on a.dataset_id = d.id and a.aom_id = ?
          where (d.aom_id = ? or a.dataset_id is not null) and d.is_active
        )
        group by format
        """,
        unquote(format),
        unquote(aom_id),
        unquote(aom_id)
      )
    end
  end

  defmacro count_region_format(region, format) do
    quote do
      fragment(
        """
        SELECT COUNT(format) FROM resource
        JOIN dataset_geographic_view d_geo ON d_geo.dataset_id = resource.dataset_id
        WHERE d_geo.region_id = ?
        AND format = ? GROUP BY format
        """,
        unquote(region),
        unquote(format)
      )
    end
  end

  defmacro count_type_by_region(region_id, type) do
    quote do
      fragment(
        """
        SELECT COUNT(*) FROM dataset
        JOIN dataset_geographic_view d_geo ON d_geo.dataset_id = dataset.id
        WHERE d_geo.region_id = ? and is_active = TRUE
        AND type = ?
        """,
        unquote(region_id),
        unquote(type)
      )
    end
  end

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%Plug.Conn{} = conn, _params), do: render_features(conn, :aoms, "api-stats-aoms")

  @spec regions(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def regions(%Plug.Conn{} = conn, _params), do: render_features(conn, :regions, "api-stats-regions")

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

  def rendered_geojson(item, ecto_opts) when item in [:aoms, :regions, :quality] do
    case item do
      :aoms -> aom_features_query()
      :regions -> region_features_query()
      :quality -> quality_features_query()
    end
    |> Repo.all(ecto_opts)
    |> features()
    |> geojson()
    |> Jason.encode!()
  end

  def rendered_geojson(:vehicles_sharing, ecto_opts) do
    vehicles_sharing_features_query()
    |> Repo.all(ecto_opts)
    |> vehicles_sharing_features()
    |> geojson()
    |> Jason.encode!()
  end

  @spec aom_features_query :: Ecto.Query.t()
  defp aom_features_query do
    nb_aggregates_dataset_by_aom =
      AOM
      |> join(:inner, [aom], d in assoc(aom, :legal_owners_dataset), as: :legal_owners_dataset)
      |> where(
        [legal_owners_dataset: d],
        d.id in subquery(
          Dataset.base_query()
          |> join(:inner, [dataset: d], aom in assoc(d, :legal_owners_aom), as: :aom)
          |> group_by([dataset: d], d.id)
          |> having([aom: a], count(a.id) >= 2)
          |> select([dataset: d], d.id)
        )
      )
      |> group_by([aom], aom.id)
      |> select([aom, legal_owners_dataset: d], %{aom_id: aom.id, count: count(d.id)})

    AOM
    |> join(:left, [aom], d in subquery(nb_aggregates_dataset_by_aom),
      on: aom.id == d.aom_id,
      as: :aggregates_by_aom
    )
    |> select([aom, aggregates_by_aom: d], %{
      geometry: aom.geom,
      id: aom.id,
      created_after_2021: aom.composition_res_id >= 1_000,
      insee_commune_principale: aom.insee_commune_principale,
      nb_datasets: fragment("select count(id) from dataset where aom_id = ? and is_active", aom.id),
      dataset_formats: %{
        gtfs: count_aom_format(aom.id, "GTFS"),
        netex: count_aom_format(aom.id, "NeTEx"),
        gtfs_rt: count_aom_format(aom.id, "gtfs-rt"),
        gbfs: count_aom_format(aom.id, "gbfs"),
        siri: count_aom_format(aom.id, "SIRI"),
        siri_lite: count_aom_format(aom.id, "SIRI Lite")
      },
      nom: aom.nom,
      forme_juridique: aom.forme_juridique,
      dataset_types: %{
        pt: count_aom_types(aom.id, "public-transit"),
        vehicles_sharing: count_aom_types(aom.id, "vehicles-sharing")
      },
      nb_other_datasets: coalesce(d.count, 0)
    })
  end

  @spec region_features_query :: Ecto.Query.t()
  defp region_features_query do
    Region
    |> select([r], %{
      geometry: r.geom,
      id: r.id,
      nom: r.nom,
      is_completed: r.is_completed,
      nb_datasets:
        fragment(
          """
          SELECT COUNT(*) FROM dataset
          JOIN dataset_geographic_view d_geo ON d_geo.dataset_id = dataset.id
          WHERE d_geo.region_id = ?
          AND is_active=TRUE
          """,
          r.id
        ),
      dataset_formats: %{
        gtfs: count_region_format(r.id, "GTFS"),
        netex: count_region_format(r.id, "NeTEx"),
        gtfs_rt: count_region_format(r.id, "gtfs-rt"),
        gbfs: count_region_format(r.id, "gbfs"),
        siri: count_region_format(r.id, "SIRI"),
        siri_lite: count_region_format(r.id, "SIRI Lite")
      },
      dataset_types: %{
        pt: count_type_by_region(r.id, "public-transit"),
        vehicles_sharing: count_type_by_region(r.id, "vehicles-sharing")
      }
    })
  end

  @spec vehicles_sharing_features_query :: Ecto.Query.t()
  def vehicles_sharing_features_query do
    DatasetGeographicView
    |> join(:left, [gv], dataset in Dataset, on: dataset.id == gv.dataset_id)
    |> select([gv, dataset], %{
      geometry: fragment("ST_Centroid(geom) as geometry"),
      names: fragment("array_agg(? order by ? asc)", dataset.custom_title, dataset.custom_title),
      slugs: fragment("array_agg(? order by ? asc)", dataset.slug, dataset.custom_title)
    })
    |> where([_gv, dataset], dataset.type == "vehicles-sharing" and dataset.is_active)
    |> group_by(fragment("geometry"))
  end

  @spec quality_features_query :: Ecto.Query.t()
  def quality_features_query do
    dt = Date.utc_today() |> Date.to_iso8601()

    error_info_sub = dataset_error_levels()
    expired_info_sub = dataset_expiration_dates()

    AOM
    |> join(:left, [a], d in assoc(a, :legal_owners_dataset), as: :legal_owners_dataset)
    |> join(:left, [a, legal_owners_dataset: legal_owners_dataset], d in Dataset,
      on: (d.id == legal_owners_dataset.id or d.aom_id == a.id) and d.is_active,
      as: :dataset
    )
    |> join(:left, [dataset: d], error_info in subquery(error_info_sub),
      on: error_info.dataset_id == d.id,
      as: :error_info
    )
    |> join(:left, [dataset: d], expired_info in subquery(expired_info_sub),
      on: expired_info.dataset_id == d.id,
      as: :expired_info
    )
    |> select(
      [aom, error_info: error_info, expired_info: expired_info],
      %{
        geometry: aom.geom,
        id: aom.id,
        created_after_2021: aom.composition_res_id >= 1_000,
        insee_commune_principale: aom.insee_commune_principale,
        nom: aom.nom,
        forme_juridique: aom.forme_juridique,
        dataset_types: %{
          pt: count_aom_types(aom.id, "public-transit", include_aggregates: true),
          vehicles_sharing: count_aom_types(aom.id, "vehicles-sharing", include_aggregates: true)
        },
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
    |> group_by([aom], aom.id)
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
end
