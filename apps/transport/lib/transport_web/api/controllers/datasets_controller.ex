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
    datasets_with_gtfs_metadata =
      DB.Dataset.base_query()
      |> DB.Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
      |> preload([resource: r, resource_history: rh, multi_validation: mv, metadata: m], [
        :aom,
        :region,
        :communes,
        resources: {r, resource_history: {rh, validations: {mv, metadata: m}}}
      ])
      |> Repo.all()

    recent_limit = Transport.Jobs.GTFSRTEntitiesJob.datetime_limit()

    datasets_with_gtfs_rt_metadata =
      DB.Dataset.base_query()
      |> DB.Resource.join_dataset_with_resource()
      |> DB.ResourceMetadata.join_resource_with_metadata()
      |> where([resource: r], r.format == "gtfs-rt")
      |> where([metadata: rm], rm.inserted_at > ^recent_limit)
      |> preload([resource: r, metadata: m], resources: {r, resource_metadata: m})
      |> DB.Repo.all()

    datasets_with_metadata =
      datasets_with_gtfs_metadata
      |> Kernel.++(datasets_with_gtfs_rt_metadata)
      |> Enum.group_by(& &1.id, & &1.resources)
      |> Enum.map(fn {dataset_id, resources} -> {dataset_id, List.flatten(resources)} end)
      |> Enum.into(%{})

    existing_ids =
      datasets_with_metadata
      |> Enum.map(fn {dataset_id, resources} ->
        {dataset_id,
         resources
         |> Enum.map(fn resource -> {resource.id, resource} end)
         |> Enum.into(%{})}
      end)
      |> Enum.into(%{})

    data =
      %{}
      |> Dataset.list_datasets()
      |> preload([:resources, :aom, :region, :communes])
      |> Repo.all()
      |> Enum.map(fn dataset ->
        enriched_dataset = Map.get(existing_ids, dataset.id)

        if enriched_dataset do
          enriched_resources =
            dataset.resources
            |> Enum.map(fn r -> enriched_dataset |> Map.get(r.id, r) end)

          Map.put(dataset, :resources, enriched_resources)
        else
          dataset
        end
      end)
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
      gtfs_resources_with_metadata =
        DB.Resource.base_query()
        |> DB.ResourceHistory.join_resource_with_latest_resource_history()
        |> DB.MultiValidation.join_resource_history_with_latest_validation(
          Transport.Validators.GTFSTransport.validator_name()
        )
        |> DB.ResourceMetadata.join_validation_with_metadata()
        |> preload([resource_history: rh, multi_validation: mv, metadata: m],
          resource_history: {rh, validations: {mv, metadata: m}}
        )
        |> where([resource: r], r.dataset_id == ^dataset.id)
        |> select([resource: r], {r.id, r})
        |> DB.Repo.all()

      recent_limit = Transport.Jobs.GTFSRTEntitiesJob.datetime_limit()

      gtfs_rt_resources_with_metadata =
        DB.Resource.base_query()
        |> DB.ResourceMetadata.join_resource_with_metadata()
        |> where([metadata: rm], rm.inserted_at > ^recent_limit)
        |> where([resource: r], r.dataset_id == ^dataset.id)
        |> preload([metadata: m], resource_metadata: m)
        |> select([resource: r], {r.id, r})
        |> DB.Repo.all()

      resources_with_metadata = Enum.into(gtfs_resources_with_metadata ++ gtfs_rt_resources_with_metadata, %{})

      enriched_resources =
        dataset
        |> Dataset.official_resources()
        |> Enum.map(fn r -> resources_with_metadata |> Map.get(r.id, r) end)

      dataset = dataset |> Map.put(:resources, enriched_resources)

      data = transform_dataset_with_detail(conn, dataset)
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
  defp transform_dataset(%Plug.Conn{} = conn, %Dataset{} = dataset),
    do: %{
      "datagouv_id" => dataset.datagouv_id,
      # to help discoverability, we explicitly add the datagouv_id as the id
      # (since it's used in /dataset/:id)
      "id" => dataset.datagouv_id,
      "title" => dataset.custom_title,
      "created_at" => dataset.created_at,
      "page_url" => TransportWeb.Router.Helpers.dataset_url(conn, :details, dataset.slug),
      "slug" => dataset.slug,
      "updated" => Helpers.last_updated(Dataset.official_resources(dataset)),
      "resources" => Enum.map(dataset.resources, &transform_resource/1),
      "community_resources" => Enum.map(Dataset.community_resources(dataset), &transform_resource/1),
      # DEPRECATED, only there for retrocompatibility, use covered_area instead
      "aom" => transform_aom(dataset.aom),
      "covered_area" => covered_area(dataset),
      "type" => dataset.type,
      "licence" => dataset.licence,
      "publisher" => get_publisher(dataset)
    }

  @spec get_publisher(Dataset.t()) :: map()
  defp get_publisher(dataset),
    do: %{
      "name" => dataset.organization,
      "type" => "organization"
    }

  @spec transform_dataset_with_detail(Plug.Conn.t(), Dataset.t() | map()) :: map()
  defp transform_dataset_with_detail(%Plug.Conn{} = conn, %Dataset{} = dataset) do
    conn
    |> transform_dataset(dataset)
    |> Map.put(
      "history",
      Transport.History.Fetcher.history_resources(dataset, TransportWeb.DatasetView.max_nb_history_resources())
    )
  end

  defp get_metadata(%Resource{format: "GTFS", resource_history: resource_history}) do
    resource_history
    |> Enum.at(0)
    |> Map.get(:validations)
    |> Enum.at(0)
    |> Map.get(:metadata)
  rescue
    _ -> nil
  end

  defp get_metadata(%Resource{format: "gtfs-rt", resource_metadata: resource_metadata}) do
    features =
      resource_metadata
      |> Enum.map(& &1.features)
      |> Enum.concat()
      |> Enum.uniq()

    %{features: features}
  rescue
    _ -> nil
  end

  defp get_metadata(_), do: nil

  @spec transform_resource(Resource.t()) :: map()
  defp transform_resource(resource) do
    metadata = get_metadata(resource)

    metadata_content =
      case metadata do
        %{metadata: metadata_content} -> metadata_content
        _ -> nil
      end

    %{
      "page_url" => TransportWeb.Router.Helpers.resource_url(TransportWeb.Endpoint, :details, resource.id),
      "datagouv_id" => resource.datagouv_id,
      "title" => resource.title,
      "updated" => Shared.DateTimeDisplay.format_naive_datetime_to_paris_tz(resource.last_update),
      "is_available" => resource.is_available,
      "url" => resource.latest_url,
      "original_url" => resource.url,
      "end_calendar_validity" => metadata_content && Map.get(metadata, "end_date"),
      "start_calendar_validity" => metadata_content && Map.get(metadata, "start_date"),
      "type" => resource.type,
      "format" => resource.format,
      "community_resource_publisher" => resource.community_resource_publisher,
      "metadata" => metadata_content,
      "original_resource_url" => resource.original_resource_url,
      "filesize" => resource.filesize,
      "modes" => metadata && Map.get(metadata, :modes),
      "features" => metadata && Map.get(metadata, :features),
      "schema_name" => resource.schema_name,
      "schema_version" => resource.schema_version
    }
    |> Enum.filter(fn {_, v} -> !is_nil(v) end)
    |> Enum.into(%{})
  end

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
