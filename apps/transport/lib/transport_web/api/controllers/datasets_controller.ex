defmodule TransportWeb.API.DatasetController do
  use TransportWeb, :controller
  alias Helpers
  alias OpenApiSpex.Operation
  alias DB.{AOM, Dataset, Repo, Resource}
  alias TransportWeb.API.Schemas.{DatasetsResponse, GeoJSONResponse}
  alias Geo.{JSON, MultiPolygon}

  @spec open_api_operation(any) :: Operation.t()
  def open_api_operation(action), do: apply(__MODULE__, :"#{action}_operation", [])

  @spec datasets_operation() :: Operation.t()
  def datasets_operation,
    do: %Operation{
      tags: ["datasets"],
      summary: "Show datasets and its resources",
      description: "For every dataset, show its associated resources, url and validity date",
      operationId: "API.DatasetController.datasets",
      parameters: [],
      responses: %{
        200 => Operation.response("Dataset", "application/json", DatasetsResponse)
      }
    }

  @spec datasets(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def datasets(%Plug.Conn{} = conn, _params) do
    data =
      %{}
      |> Dataset.list_datasets()
      |> Repo.all()
      |> Repo.preload([:resources, :aom, :region, :communes])
      |> Enum.map(fn d -> transform_dataset(conn, d) end)

    render(conn, %{data: data})
  end

  @spec by_id_operation() :: Operation.t()
  def by_id_operation,
    do: %Operation{
      tags: ["datasets"],
      summary: "Show given dataset and its resources",
      description: "For one dataset, show its associated resources, url and validity date",
      operationId: "API.DatasetController.datasets_by_id",
      parameters: [Operation.parameter(:id, :path, :string, "id")],
      responses: %{
        200 => Operation.response("Dataset", "application/json", DatasetsResponse)
      }
    }

  @spec geojson_by_id_operation() :: Operation.t()
  def geojson_by_id_operation,
    do: %Operation{
      tags: ["datasets"],
      summary: "Show given dataset geojson",
      description: "For one dataset, show its associated geojson",
      operationId: "API.DatasetController.datasets_geojson_by_id",
      parameters: [Operation.parameter(:id, :path, :string, "id")],
      responses: %{
        200 => Operation.response("Dataset", "application/json", GeoJSONResponse)
      }
    }

  @spec by_id(Plug.Conn.t(), map) :: Plug.Conn.t()
  def by_id(%Plug.Conn{} = conn, %{"id" => id}) do
    Dataset
    |> Repo.get_by(datagouv_id: id)
    |> Repo.preload([:resources, :aom, :region, :communes])
    |> case do
      %Dataset{} = dataset ->
        conn
        |> assign(:data, transform_dataset_with_detail(conn, dataset))
        |> render()

      nil ->
        conn
        |> put_status(404)
        |> render(%{errors: "dataset not found"})
    end
  end

  @spec geojson_by_id(Plug.Conn.t(), map) :: Plug.Conn.t()
  def geojson_by_id(%Plug.Conn{} = conn, %{"id" => id}) do
    Dataset
    |> Repo.get_by(datagouv_id: id)
    |> Repo.preload([:aom, :region, :communes])
    |> case do
      %Dataset{} = dataset ->
        data =
          case {dataset.aom, dataset.region, dataset.communes} do
            {aom, _, _} when not is_nil(aom) ->
              [to_feature(aom.geom, aom.nom)] |> keep_valid_features()

            {_, region, _} when not is_nil(region) ->
              [to_feature(region.geom, region.nom)] |> keep_valid_features()

            {_, _, communes} when not is_nil(communes) ->
              communes |> Enum.map(fn c -> to_feature(c.geom, c.nom) end) |> keep_valid_features()

            _ ->
              []
          end

        conn
        |> assign(:data, to_geojson(dataset, data))
        |> render()

      nil ->
        conn
        |> put_status(404)
        |> render(%{errors: "dataset not found"})
    end
  end

  @spec keep_valid_features([{:ok, %{}} | :error]) :: [%{}]
  defp keep_valid_features(list) do
    list
    |> Enum.filter(fn f ->
      case f do
        {:ok, _g} -> true
        _ -> false
      end
    end)
    |> Enum.map(fn {:ok, g} -> g end)
  end

  @spec to_feature(MultiPolygon.t(), binary) :: {:ok, %{}} | :error
  defp to_feature(geom, name) do
    case JSON.encode(geom) do
      {:ok, g} -> {:ok, %{"geometry" => g, "type" => "Feature", "properties" => %{"name" => name}}}
      _ -> :error
    end
  end

  @spec to_geojson(Dataset.t(), [map()]) :: map()
  defp to_geojson(dataset, features),
    do: %{
      "type" => "FeatureCollection",
      "name" => "Dataset #{dataset.slug}",
      "features" => features
    }

  @spec transform_dataset(Plug.Conn.t(), Dataset.t()) :: map()
  defp transform_dataset(%Plug.Conn{} = conn, dataset),
    do: %{
      "datagouv_id" => dataset.datagouv_id,
      # to help discoverability, we explicitly add the datagouv_id as the id
      # (since it's used in /dataset/:id)
      "id" => dataset.datagouv_id,
      "title" => dataset.spatial,
      "created_at" => dataset.created_at,
      "page_url" => TransportWeb.Router.Helpers.dataset_url(conn, :details, dataset.slug),
      "slug" => dataset.slug,
      "updated" => Helpers.last_updated(Dataset.official_resources(dataset)),
      "resources" => Enum.map(Dataset.official_resources(dataset), &transform_resource/1),
      "community_resources" => Enum.map(Dataset.community_resources(dataset), &transform_resource/1),
      # DEPRECATED, only there for retrocompatibility, use covered_area instead
      "aom" => transform_aom(dataset.aom),
      "covered_area" => covered_area(dataset),
      "type" => dataset.type,
      "publisher" => get_publisher(dataset)
    }

  @spec get_publisher(Dataset.t()) :: map()
  defp get_publisher(dataset),
    do: %{
      "name" => dataset.organization,
      "type" => "organization"
    }

  @spec transform_dataset_with_detail(Plug.Conn.t(), Dataset.t()) :: map()
  defp transform_dataset_with_detail(%Plug.Conn{} = conn, dataset) do
    conn
    |> transform_dataset(dataset)
    |> Map.put("history", Dataset.history_resources(dataset))
  end

  @spec transform_resource(Resource.t()) :: map()
  defp transform_resource(resource),
    do:
      %{
        "datagouv_id" => resource.datagouv_id,
        "title" => resource.title,
        "updated" => Helpers.format_datetime(resource.last_update),
        "url" => resource.latest_url,
        "original_url" => resource.url,
        "end_calendar_validity" => resource.metadata["end_date"],
        "start_calendar_validity" => resource.metadata["start_date"],
        "format" => resource.format,
        "content_hash" => resource.content_hash,
        "community_resource_publisher" => resource.community_resource_publisher,
        "metadata" => resource.metadata,
        "original_resource_url" => resource.original_resource_url
      }
      |> Enum.filter(fn {_, v} -> !is_nil(v) end)
      |> Enum.into(%{})

  @spec transform_aom(AOM.t() | nil) :: map()
  defp transform_aom(nil), do: %{"name" => nil}
  defp transform_aom(aom), do: %{"name" => aom.nom, "siren" => aom.siren}

  @spec covered_area(Dataset.t()) :: map()
  defp covered_area(%Dataset{aom: aom}) when not is_nil(aom),
    do: %{"type" => "aom", "name" => aom.nom, "aom" => %{"name" => aom.nom, "siren" => aom.siren}}

  defp covered_area(%Dataset{region: %{id: 14}}),
    do: %{"type" => "country", "name" => "France", "country" => %{"name" => "France"}}

  defp covered_area(%Dataset{region: %{nom: nom}}),
    do: %{"type" => "region", "name" => nom, "region" => %{"name" => nom}}

  defp covered_area(%Dataset{communes: [_ | _] = c, associated_territory_name: nom}),
    do: %{"type" => "cities", "name" => nom, "cities" => transform_cities(c)}

  defp covered_area(_) do
    %{}
  end

  defp transform_cities(cities) do
    cities
    |> Enum.map(fn c -> %{"name" => c.nom, "insee" => c.insee} end)
  end
end
