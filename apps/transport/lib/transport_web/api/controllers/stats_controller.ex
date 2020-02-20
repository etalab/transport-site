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

  def nb_non_standard_rt(insee_commune_principale) do
    CSVDocuments.real_time_providers()
    |> Enum.filter(fn p -> p["aom_insee_principal"] == insee_commune_principale end)
    |> Enum.to_list()
    |> length
  end

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

  @spec aom_features :: Ecto.Query.t()
  defp aom_features do
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
      parent_dataset_slug: dataset.slug,
      parent_dataset_name: dataset.title
    })
  end

  def index(%Plug.Conn{} = conn, _params) do
    render(
      conn,
      %{data: aom_features() |> features() |> geojson()}
    )
  end

  def regions(%Plug.Conn{} = conn, _params) do
    render(conn, %{
      data:
        geojson(
          features(
            from(r in Region,
              select: %{
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
                  pt:
                    fragment(
                      """
                      SELECT COUNT(*) FROM dataset
                      JOIN dataset_geographic_view d_geo ON d_geo.dataset_id = dataset.id
                      WHERE d_geo.region_id = ?
                      AND type = 'public-transit'
                      """,
                      r.id
                    ),
                  bike_sharing:
                    fragment(
                      """
                      SELECT COUNT(*) FROM dataset
                      JOIN dataset_geographic_view d_geo ON d_geo.dataset_id = dataset.id
                      WHERE d_geo.region_id = ?
                      AND type = 'bike-sharing'
                      """,
                      r.id
                    )
                }
              }
            )
          )
        )
    })
  end

  @spec bike_sharing(Plug.Conn.t(), any) :: Plug.Conn.t()
  def bike_sharing(%Plug.Conn{} = conn, _params) do
    render(conn, %{
      data:
        geojson(
          features(
            from(gv in DatasetGeographicView,
              left_join: d in Dataset,
              on: d.id == gv.dataset_id,
              select: %{
                geometry: gv.geom,
                id: gv.dataset_id,
                nom: d.spatial,
                parent_dataset_slug: d.slug
              },
              where: d.type == "bike-sharing"
            )
          )
        )
    })
  end
end
