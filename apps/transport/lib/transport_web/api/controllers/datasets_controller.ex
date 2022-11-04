defmodule TransportWeb.API.DatasetController do
  use TransportWeb, :controller
  import Ecto.Query
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
    datasets_with_metadata =
      Transport.Validators.GTFSTransport.validator_name()
      |> Dataset.join_from_dataset_to_metadata()
      |> preload([:resources, :aom, :region, :communes])
      |> select([metadata: rm, dataset: d, multi_validation: mv, resource_history: rh], %{
        dataset: d,
        metadata: rm,
        multi_validation: {mv.id, mv.resource_history_id},
        resource_history: {rh.id, rh.resource_id}
      })
      |> Repo.all()

    existing_ids = datasets_with_metadata |> Enum.map(& &1.dataset.id)

    data =
      %{}
      |> Dataset.list_datasets()
      |> where([dataset: d], d.id not in ^existing_ids)
      |> preload([:resources, :aom, :region, :communes])
      |> Repo.all()
      |> Enum.concat(datasets_with_metadata)
      |> Enum.map(&transform_dataset(conn, &1))

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
    dataset =
      Dataset
      |> preload([:resources, :aom, :region, :communes])
      |> Repo.get_by(datagouv_id: id)

    if is_nil(dataset) do
      conn |> put_status(404) |> render(%{errors: "dataset not found"})
    else
      # This is just a temporary hotfix for https://github.com/etalab/transport-site/issues/2752
      records =
        Transport.Validators.GTFSTransport.validator_name()
        |> Dataset.join_from_dataset_to_metadata()
        |> where([dataset: d], d.datagouv_id == ^id)
        |> preload([:resources, :aom, :region, :communes])
        |> select([metadata: rm, dataset: d, multi_validation: mv, resource_history: rh], %{
          dataset: d,
          metadata: rm,
          multi_validation: {mv.id, mv.resource_history_id},
          resource_history: {rh.id, rh.resource_id}
        })
        |> DB.Repo.all()

      # the query above returns more than one record ; for now and without proper time
      # to fix the code to return the correct one, I'm returning nothing
      result = if records |> Enum.count() > 1, do: nil, else: records |> Enum.at(0)

      data =
        if is_nil(result) do
          transform_dataset_with_detail(conn, dataset)
        else
          transform_dataset_with_detail(conn, %{result | dataset: dataset})
        end

      conn |> assign(:data, data) |> render()
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

  @spec transform_dataset(Plug.Conn.t(), Dataset.t() | map()) :: map()
  defp transform_dataset(%Plug.Conn{} = conn, %Dataset{} = dataset) do
    transform_dataset(conn, %{dataset: dataset, metadata: []})
  end

  defp transform_dataset(%Plug.Conn{} = conn, %{dataset: dataset, metadata: metadata} = result) do
    # Plug DB.ResourceMetadata into its associated DB.Resource
    metadata =
      [metadata]
      |> List.flatten()
      |> Enum.into(%{}, fn metadata ->
        resource_id =
          result.resource_history
          |> maybe_map()
          |> Map.fetch!(Map.fetch!(result.multi_validation |> maybe_map(), metadata.multi_validation_id))

        {resource_id, metadata}
      end)

    resources =
      dataset
      |> Dataset.official_resources()
      |> Enum.map(fn resource ->
        metadata = Map.get(metadata, resource.id, %{})
        fields = Enum.into([:modes, :features, :metadata], %{}, &{&1, Map.get(metadata, &1)})
        Map.merge(resource, fields)
      end)

    %{
      "datagouv_id" => dataset.datagouv_id,
      # to help discoverability, we explicitly add the datagouv_id as the id
      # (since it's used in /dataset/:id)
      "id" => dataset.datagouv_id,
      "title" => dataset.custom_title,
      "created_at" => dataset.created_at,
      "page_url" => TransportWeb.Router.Helpers.dataset_url(conn, :details, dataset.slug),
      "slug" => dataset.slug,
      "updated" => Helpers.last_updated(Dataset.official_resources(dataset)),
      "resources" => Enum.map(resources, &transform_resource/1),
      "community_resources" => Enum.map(Dataset.community_resources(dataset), &transform_resource/1),
      # DEPRECATED, only there for retrocompatibility, use covered_area instead
      "aom" => transform_aom(dataset.aom),
      "covered_area" => covered_area(dataset),
      "type" => dataset.type,
      "licence" => dataset.licence,
      "publisher" => get_publisher(dataset)
    }
  end

  defp maybe_map(el) when is_map(el), do: el
  defp maybe_map(el) when is_list(el), do: Enum.into(el, %{})
  defp maybe_map(el) when is_tuple(el), do: Enum.into([el], %{})

  @spec get_publisher(Dataset.t()) :: map()
  defp get_publisher(dataset),
    do: %{
      "name" => dataset.organization,
      "type" => "organization"
    }

  @spec transform_dataset_with_detail(Plug.Conn.t(), Dataset.t() | map()) :: map()
  defp transform_dataset_with_detail(%Plug.Conn{} = conn, %Dataset{} = dataset) do
    transform_dataset_with_detail(conn, %{dataset: dataset, metadata: []})
  end

  defp transform_dataset_with_detail(%Plug.Conn{} = conn, %{dataset: %DB.Dataset{} = dataset} = result) do
    conn
    |> transform_dataset(result)
    |> Map.put(
      "history",
      Transport.History.Fetcher.history_resources(dataset, TransportWeb.DatasetView.max_nb_history_resources())
    )
  end

  @spec transform_resource(Resource.t()) :: map()
  defp transform_resource(resource),
    do:
      %{
        "datagouv_id" => resource.datagouv_id,
        "title" => resource.title,
        "updated" => Shared.DateTimeDisplay.format_naive_datetime_to_paris_tz(resource.last_update),
        "url" => resource.latest_url,
        "original_url" => resource.url,
        "end_calendar_validity" => resource.metadata["end_date"],
        "start_calendar_validity" => resource.metadata["start_date"],
        "type" => resource.type,
        "format" => resource.format,
        "content_hash" => resource.content_hash,
        "community_resource_publisher" => resource.community_resource_publisher,
        "metadata" => resource.metadata,
        "original_resource_url" => resource.original_resource_url,
        "filesize" => resource.filesize,
        "modes" => resource.modes,
        "features" => resource.features,
        "schema_name" => resource.schema_name,
        "schema_version" => resource.schema_version
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
