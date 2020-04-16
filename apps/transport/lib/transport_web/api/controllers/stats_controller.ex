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

  @spec bike_sharing_operation() :: Operation.t()
  def bike_sharing_operation,
    do: %Operation{
      tags: ["bike-sharing"],
      summary: "Show bike sharing stats",
      description: "Show bike sharing stats",
      operationId: "API.StatsController.bike_sharing",
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
            # negative values are up to date datasets, we filter them
            "expired_from" => aom |> Map.get(:quality, %{}) |> Map.get(:expired_from) |> filter_neg,
            "error_level" => aom |> Map.get(:quality, %{}) |> Map.get(:error_level)
          },
          "dataset_formats" =>
            aom
            |> Map.get(:dataset_formats, [])
            |> Enum.filter(fn {_, v} -> v != nil end)
            |> Enum.into(%{})
            |> Map.put("non_standard_rt", nb_non_standard_rt(Map.get(aom, :insee_commune_principale))),
          "dataset_types" =>
            aom
            |> Map.get(:dataset_types, [])
            |> Enum.filter(fn {_, v} -> v != nil end)
            |> Enum.into(%{})
        }
      }
    end)
    |> Enum.to_list()
  end

  defmacro count_aom_format(aom, format) do
    quote do
      fragment("SELECT COUNT(format) FROM resource \
      WHERE dataset_id in \
      (SELECT id FROM dataset WHERE aom_id=?) \
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
  def index(%Plug.Conn{} = conn, _params), do: render_features(conn, aom_features())

  @spec regions(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def regions(%Plug.Conn{} = conn, _params), do: render_features(conn, region_features())

  @spec bike_sharing(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def bike_sharing(%Plug.Conn{} = conn, _params), do: render_features(conn, bike_sharing_features())

  @spec render_features(Plug.Conn.t(), Ecto.Query.t()) :: Plug.Conn.t()
  defp render_features(conn, query), do: render(conn, %{data: query |> features() |> geojson()})

  @spec aom_features :: Ecto.Query.t()
  defp aom_features do
    dt = Date.utc_today() |> Date.to_iso8601()

    AOM
    |> join(:left, [aom], dataset in Dataset, on: dataset.id == aom.parent_dataset_id)
    |> select([aom, dataset], %{
      geometry: aom.geom,
      id: aom.id,
      insee_commune_principale: aom.insee_commune_principale,
      nb_datasets: fragment("SELECT COUNT(*) FROM dataset WHERE aom_id=?", aom.id),
      dataset_formats: %{
        gtfs: count_aom_format(aom.id, "GTFS"),
        netex: count_aom_format(aom.id, "netex"),
        gtfs_rt: count_aom_format(aom.id, "gtfs-rt"),
        gbfs: count_aom_format(aom.id, "gbfs")
      },
      nom: aom.nom,
      forme_juridique: aom.forme_juridique,
      dataset_types: %{
        pt: fragment("SELECT COUNT(*) FROM dataset WHERE aom_id=? AND type = 'public-transit'", aom.id),
        bike_sharing: fragment("SELECT COUNT(*) FROM dataset WHERE aom_id=? AND type = 'bike-sharing'", aom.id)
      },
      quality: %{
        # we get the number of day since the latest resource is expired
        expired_from:
          fragment(
            """
            SELECT
            TO_DATE(?, 'YYYY-MM-DD') - TO_DATE(max(metadata->>'end_date'), 'YYYY-MM-DD')
            FROM resource
            WHERE
            metadata->>'end_date' IS NOT NULL
            AND dataset_id in
              (SELECT id FROM dataset WHERE aom_id=?)
            """,
            ^dt,
            aom.id
          ),
        # we get the most serious error of the valid resources
        error_level:
          fragment(
            """
            SELECT severity from (
              SELECT distinct(json_data.value#>>'{0,severity}') as severity
              FROM validations
              JOIN resource ON resource.id = validations.resource_id
              join dataset ON dataset.id = resource.dataset_id,
              json_each(validations.details) json_data
              WHERE
              dataset.aom_id = ?
              -- we only consider valid resources
              AND resource.metadata->>'end_date' IS NOT NULL
              AND resource.metadata->>'end_date' > ?
            ) as severities
            ORDER BY (
              CASE severity::text
                WHEN 'Fatal' THEN 1
                WHEN 'Error' THEN 2
                WHEN 'Warning' THEN 3
                WHEN 'Information' THEN 4
                WHEN 'Irrelevant' THEN 5
                END
            ) ASC
            LIMIT 1
            """,
            aom.id,
            ^dt
          )
      },
      parent_dataset_slug: dataset.slug,
      parent_dataset_name: dataset.title
    })
  end

  @spec region_features :: Ecto.Query.t()
  defp region_features do
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
          """,
          r.id
        ),
      dataset_formats: %{
        gtfs: count_region_format(r.id, "GTFS"),
        netex: count_region_format(r.id, "netex"),
        gtfs_rt: count_region_format(r.id, "gtfs-rt"),
        gbfs: count_region_format(r.id, "gbfs")
      },
      dataset_types: %{
        pt: count_type_by_region(r.id, "public-transit"),
        bike_sharing: count_type_by_region(r.id, "bike-sharing")
      }
    })
  end

  @spec bike_sharing_features :: Ecto.Query.t()
  defp bike_sharing_features do
    DatasetGeographicView
    |> join(:left, [gv], dataset in Dataset, on: dataset.id == gv.dataset_id)
    |> select([gv, dataset], %{
      geometry: fragment("ST_Centroid(geom)"),
      id: gv.dataset_id,
      nom: dataset.spatial,
      parent_dataset_slug: dataset.slug
    })
    |> where([_gv, dataset], dataset.type == "bike-sharing")
  end
end
