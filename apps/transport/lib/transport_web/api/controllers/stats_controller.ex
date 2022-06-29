defmodule TransportWeb.API.StatsController do
  use TransportWeb, :controller
  alias DB.{AOM, Dataset, DatasetGeographicView, Region, Repo}
  import Ecto.Query
  alias Geo.JSON
  alias OpenApiSpex.Operation
  alias Transport.CSVDocuments
  alias TransportWeb.API.Schemas.GeoJSONResponse

  @spec open_api_operation(any) :: Operation.t()
  def open_api_operation(action), do: apply(__MODULE__, :"#{action}_operation", [])

  @spec regions_operation() :: Operation.t()
  def regions_operation,
    do: %Operation{
      tags: ["regions"],
      summary: "Show regions",
      description: "Show covered french administrative regions",
      operationId: "API.StatsController.regions",
      parameters: [],
      responses: %{
        200 => Operation.response("GeoJSON", "application/json", GeoJSONResponse)
      }
    }

  @spec index_operation() :: Operation.t()
  def index_operation,
    do: %Operation{
      tags: ["index"],
      summary: "Show regions",
      description: "Show covered french administrative regions",
      operationId: "API.StatsController.index",
      parameters: [],
      responses: %{
        200 => Operation.response("GeoJSON", "application/json", GeoJSONResponse)
      }
    }

  @spec bike_scooter_sharing_operation() :: Operation.t()
  def bike_scooter_sharing_operation,
    do: %Operation{
      tags: ["bike-scooter-sharing"],
      summary: "Show bike and scooter sharing stats",
      description: "Show bike and scooter sharing stats",
      operationId: "API.StatsController.bike_scooter_sharing",
      parameters: [],
      responses: %{
        200 => Operation.response("GeoJSON", "application/json", GeoJSONResponse)
      }
    }

  @spec quality_operation() :: Operation.t()
  def quality_operation,
    do: %Operation{
      tags: ["quality"],
      summary: "Show data quality stats",
      description: "Show data quality stats",
      operationId: "API.StatsController.quality",
      parameters: [],
      responses: %{
        200 => Operation.response("GeoJSON", "application/json", GeoJSONResponse)
      }
    }

  @spec geojson([map()]) :: map()
  def geojson(features),
    do: %{
      "type" => "FeatureCollection",
      "name" => "Autorités organisatrices de Mobiltés",
      "features" => features
    }

  @spec nb_non_standard_rt(binary()) :: non_neg_integer()
  def nb_non_standard_rt(insee_commune_principale) do
    CSVDocuments.real_time_providers()
    |> Enum.filter(fn p -> p["aom_insee_principal"] == insee_commune_principale end)
    |> Enum.to_list()
    |> length
  end

  @spec filter_neg(nil | integer()) :: nil | non_neg_integer()
  defp filter_neg(nil), do: nil

  defp filter_neg(val) when val < 0, do: nil
  defp filter_neg(val) when val >= 0, do: val

  @spec features(Ecto.Query.t()) :: [map()]
  def features(q) do
    q
    |> Repo.all()
    |> Enum.filter(fn aom -> !is_nil(aom.geometry) end)
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
          "parent_dataset_slug" => Map.get(aom, :parent_dataset_slug, ""),
          "parent_dataset_name" => Map.get(aom, :parent_dataset_name, ""),
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
            |> Enum.into(%{})
            |> Map.put("non_standard_rt", nb_non_standard_rt(Map.get(aom, :insee_commune_principale))),
          "dataset_types" => dataset_types
        }
      }
    end)
    |> Enum.to_list()
  end

  defmacro count_aom_format(aom, format) do
    quote do
      fragment("SELECT COUNT(format) FROM resource \
      WHERE dataset_id in \
      (SELECT id FROM dataset WHERE aom_id=? and is_active=TRUE) \
      AND format = ? GROUP BY format", unquote(aom), unquote(format))
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
  def index(%Plug.Conn{} = conn, _params), do: render_features(conn, aom_features_query(), "api-stats-aoms")

  @spec regions(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def regions(%Plug.Conn{} = conn, _params), do: render_features(conn, region_features_query(), "api-stats-regions")

  @spec bike_scooter_sharing(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def bike_scooter_sharing(%Plug.Conn{} = conn, _params),
    do: render_features(conn, bike_scooter_sharing_features())

  @spec quality(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def quality(%Plug.Conn{} = conn, _params), do: render_features(conn, quality_features_query(), "api-stats-quality")

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
  @spec render_features(Plug.Conn.t(), Ecto.Query.t(), binary()) :: Plug.Conn.t()
  defp render_features(conn, query, cache_key) do
    comp_fn = fn ->
      query
      |> features()
      |> geojson()
      |> Jason.encode!()
    end

    data = Transport.Cache.API.fetch(cache_key, comp_fn)

    render(conn, data: {:skip_json_encoding, data})
  end

  defp render_features(conn, data) do
    render(conn, data: {:skip_json_encoding, data |> geojson() |> Jason.encode!()})
  end

  @spec aom_features_query :: Ecto.Query.t()
  defp aom_features_query do
    AOM
    |> join(:left, [aom], dataset in Dataset, on: dataset.id == aom.parent_dataset_id)
    |> select([aom, parent_dataset], %{
      geometry: aom.geom,
      id: aom.id,
      insee_commune_principale: aom.insee_commune_principale,
      nb_datasets: fragment("SELECT COUNT(*) FROM dataset WHERE aom_id=? AND is_active=TRUE ", aom.id),
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
        pt:
          fragment("SELECT COUNT(*) FROM dataset WHERE aom_id=? AND type = 'public-transit' AND is_active=TRUE", aom.id),
        bike_scooter_sharing:
          fragment(
            "SELECT COUNT(*) FROM dataset WHERE aom_id=? AND type = 'bike-scooter-sharing' AND is_active=TRUE",
            aom.id
          )
      },
      parent_dataset_slug: parent_dataset.slug,
      parent_dataset_name: parent_dataset.datagouv_title
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
        bike_scooter_sharing: count_type_by_region(r.id, "bike-scooter-sharing")
      }
    })
  end

  @spec bike_scooter_sharing_features :: []
  def bike_scooter_sharing_features do
    query =
      DatasetGeographicView
      |> join(:left, [gv], dataset in Dataset, on: dataset.id == gv.dataset_id)
      |> select([gv, dataset], %{
        geometry: fragment("ST_Centroid(geom) as geometry"),
        names: fragment("array_agg(? order by ? asc)", dataset.custom_title, dataset.custom_title),
        slugs: fragment("array_agg(? order by ? asc)", dataset.slug, dataset.custom_title)
      })
      |> where([_gv, dataset], dataset.type == "bike-scooter-sharing" and dataset.is_active)
      |> group_by(fragment("geometry"))

    query
    |> DB.Repo.all()
    |> Enum.reject(fn r -> is_nil(r.geometry) end)
    |> Enum.map(fn r ->
      %{
        "geometry" => r.geometry |> JSON.encode!(),
        "type" => "Feature",
        "properties" => Map.take(r, Enum.filter(Map.keys(r), fn k -> k != "geometry" end))
      }
    end)
  end

  @spec quality_features_query :: Ecto.Query.t()
  def quality_features_query do
    # Note: this query is not done in the meantime as aom_features_query because this query is quite long to execute
    # and we don't want to slow down the main aom_features_query to much
    dt = Date.utc_today() |> Date.to_iso8601()

    error_info_sub = dataset_error_levels()
    expired_info_sub = dataset_expiration_dates()

    DB.AOM
    |> join(:left, [aom], dataset in Dataset,
      on: dataset.id == aom.parent_dataset_id or dataset.aom_id == aom.id,
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
        insee_commune_principale: aom.insee_commune_principale,
        nom: aom.nom,
        forme_juridique: aom.forme_juridique,
        dataset_types: %{
          pt:
            fragment(
              "SELECT COUNT(*) FROM dataset WHERE aom_id=? AND type = 'public-transit' AND is_active=TRUE",
              aom.id
            ),
          bike_scooter_sharing:
            fragment(
              "SELECT COUNT(*) FROM dataset WHERE aom_id=? AND type = 'bike-scooter-sharing' AND is_active=TRUE",
              aom.id
            )
        },
        quality: %{
          expired_from: fragment("TO_DATE(?, 'YYYY-MM-DD') - max(?)", ^dt, expired_info.end_date),
          # expired_from: max(expired_info.end_date),
          error_level: fragment("case max(CASE max_error::text
              WHEN 'Fatal' THEN 1
              WHEN 'Error' THEN 2
              WHEN 'Warning' THEN 3
              WHEN 'Information' THEN 4
              WHEN 'Irrelevant' THEN 5
              WHEN 'NoError' THEN 6
              END)
            WHEN 1 THEN 'Fatal'
            WHEN 2 THEN 'Error'
            WHEN 3 THEN 'Warning'
            WHEN 4 THEN 'Information'
            WHEN 5 THEN 'Irrelevant'
            WHEN 6 THEN 'NoError'
          END
          ")
        }
      }
    )
    |> group_by([aom], aom.id)
  end

  def dataset_expiration_dates do
    Transport.Validators.GTFSTransport.validator_name()
    |> DB.Dataset.join_from_dataset_to_metadata()
    |> where([resource: r], r.is_available == true)
    |> select([dataset: d, metadata: m], %{
      dataset_id: d.id,
      end_date: fragment("TO_DATE(?->>'end_date', 'YYYY-MM-DD')", m.metadata)
    })
  end

  def dataset_error_levels do
    Transport.Validators.GTFSTransport.validator_name()
    |> DB.Dataset.join_from_dataset_to_metadata()
    |> DB.ResourceMetadata.where_gtfs_up_to_date()
    |> where([resource: r], r.is_available == true)
    |> select([dataset: d, multi_validation: mv], %{dataset_id: d.id, max_error: mv.max_error})
  end
end
