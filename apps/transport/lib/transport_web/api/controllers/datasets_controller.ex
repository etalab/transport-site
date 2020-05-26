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
      %{"type" => "public-transit"}
      |> Dataset.list_datasets()
      |> Repo.all()
      |> Repo.preload([:resources, :aom])
      |> Enum.map(&transform_dataset/1)

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
    |> Repo.preload([:resources, :aom])
    |> case do
      %Dataset{} = dataset ->
        conn
        |> assign(:data, transform_dataset_with_detail(dataset))
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
            {aom, _, _} when not is_nil(aom) -> [to_feature(aom.geom, aom.nom)]
            {_, region, _} when not is_nil(region) -> [to_feature(region.geom, region.nom)]
            {_, _, communes} when not is_nil(communes) -> communes |> Enum.map(fn c -> to_feature(c.geom, c.nom) end)
            _ -> []
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

  @spec to_feature(MultiPolygon.t(), binary) :: map()
  defp to_feature(nil, name), do: %{}

  defp to_feature(geom, name) do
    %{
      "geometry" => geom |> JSON.encode!(),
      "type" => "Feature",
      "properties" => %{
        "name" => name
      }
    }
  end

  @spec to_geojson(Dataset.t(), [map()]) :: map()
  defp to_geojson(dataset, features),
    do: %{
      "type" => "FeatureCollection",
      "name" => "Dataset #{dataset.slug}",
      "features" => features
    }

  @spec transform_dataset(Dataset.t()) :: map()
  defp transform_dataset(dataset),
    do: %{
      "datagouv_id" => dataset.datagouv_id,
      # to help discoverability, we explicitly add the datagouv_id as the id
      # (since it's used in /dataset/:id)
      "id" => dataset.datagouv_id,
      "title" => dataset.spatial,
      "created_at" => dataset.created_at,
      "updated" => Helpers.last_updated(dataset.resources),
      "resources" => Enum.map(dataset.resources, &transform_resource/1),
      "aom" => transform_aom(dataset.aom),
      "type" => dataset.type,
      "publisher" => get_publisher(dataset)
    }

  @spec get_publisher(Dataset.t()) :: map()
  defp get_publisher(dataset),
    do: %{
      "name" => dataset.organization,
      "type" => "organization"
    }

  @spec transform_dataset_with_detail(Dataset.t()) :: map()
  defp transform_dataset_with_detail(dataset) do
    dataset
    |> transform_dataset
    |> Map.put("history", Dataset.history_resources(dataset))
  end

  @spec transform_resource(Resource.t()) :: map()
  defp transform_resource(resource),
    do: %{
      "title" => resource.title,
      "updated" => Helpers.format_datetime(resource.last_update),
      "url" => resource.latest_url,
      "end_calendar_validity" => resource.metadata["end_date"],
      "start_calendar_validity" => resource.metadata["start_date"],
      "format" => resource.format,
      "content_hash" => resource.content_hash
    }

  @spec transform_aom(AOM.t() | nil) :: map()
  defp transform_aom(nil), do: %{"name" => nil}
  defp transform_aom(aom), do: %{"name" => aom.nom, "siren" => aom.siren}
end
