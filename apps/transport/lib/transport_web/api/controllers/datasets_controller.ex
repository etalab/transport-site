defmodule TransportWeb.API.DatasetController do
  use TransportWeb, :controller
  import Ecto.Query
  alias DB.{Dataset, Repo, Resource}
  alias Geo.{JSON, MultiPolygon}
  alias Helpers
  alias OpenApiSpex.Operation

  plug(:log_request when action in [:datasets, :by_id])

  # The default (one minute) felt a bit too high for someone doing scripted operations
  # (have to wait during experimentations), so I lowered it a bit. It is high enough
  # that it will still protect a lot against excessive querying.
  @index_cache_ttl Transport.PreemptiveAPICache.cache_ttl()
  @by_id_cache_ttl :timer.seconds(30)
  @offers_columns [:nom_commercial, :identifiant_offre, :type_transport, :nom_aom]
  @dataset_preload [
    :resources,
    :legal_owners_aom,
    :legal_owners_region,
    :declarative_spatial_areas,
    offers: from(o in DB.Offer, select: ^@offers_columns),
    resources: [:dataset]
  ]

  @spec open_api_operation(any) :: Operation.t()
  def open_api_operation(action), do: apply(__MODULE__, :"#{action}_operation", [])

  @spec datasets_operation() :: Operation.t()
  def datasets_operation,
    do: %Operation{
      tags: ["datasets"],
      summary: "List all datasets (with their resources)",
      description: ~s"This call returns (in a single, non-paginated response) the list of all the
                      datasets referenced on the site, along with their associated resources. The datasets
                      and resources are here provided in summarized form (without history & conversions).
                      You can call `/api/datasets/:id` for each dataset to get extra data (history & conversions)",
      operationId: "API.DatasetController.datasets",
      parameters: authorization_header(),
      responses: %{
        200 => Operation.response("DatasetsResponse", "application/json", TransportWeb.API.Schemas.DatasetsResponse)
      }
    }

  defp authorization_header do
    [
      Operation.parameter(
        :authorization,
        :header,
        :string,
        "Your token secret from your [reuser space](https://transport.data.gouv.fr/espace_reutilisateur)."
      )
    ]
  end

  @spec datasets(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def datasets(%Plug.Conn{} = conn, _params) do
    comp_fn = fn -> prepare_datasets_index_data() end

    data =
      Transport.Cache.fetch("api-datasets-index", comp_fn, @index_cache_ttl)
      |> Enum.map(&maybe_add_token_urls(&1, conn))

    render(conn, %{data: data})
  end

  def add_enriched_resources_to_dataset(dataset, nil = _enriched_dataset), do: dataset

  def add_enriched_resources_to_dataset(dataset, enriched_dataset) do
    enriched_resources =
      dataset.resources
      |> Enum.map(fn r -> enriched_dataset |> Map.get(r.id, r) end)

    Map.put(dataset, :resources, enriched_resources)
  end

  @spec by_id_operation() :: Operation.t()
  def by_id_operation,
    do: %Operation{
      tags: ["datasets"],
      summary: "Return the details of a given dataset and its resources",
      description:
        ~s"Returns the detailed version of a dataset, showing its resources, the resources history & conversions.",
      operationId: "API.DatasetController.datasets_by_id",
      parameters:
        [Operation.parameter(:id, :path, :string, "datagouv id of the dataset you want to retrieve")] ++
          authorization_header(),
      responses: %{
        200 => Operation.response("DatasetDetails", "application/json", TransportWeb.API.Schemas.DatasetDetails)
      }
    }

  @spec geojson_by_id_operation() :: Operation.t()
  def geojson_by_id_operation,
    do: %Operation{
      tags: ["datasets"],
      summary: "Show given dataset GeoJSON",
      description: "For one dataset, show its associated GeoJSON.",
      operationId: "API.DatasetController.datasets_geojson_by_id",
      parameters: [Operation.parameter(:id, :path, :string, "id")],
      responses: %{
        200 => Operation.response("Dataset", "application/json", TransportWeb.API.Schemas.GeoJSONResponse)
      }
    }

  @spec by_id(Plug.Conn.t(), map) :: Plug.Conn.t()
  def by_id(%Plug.Conn{} = conn, %{"id" => datagouv_id}) do
    dataset =
      Dataset
      |> Dataset.reject_experimental_datasets()
      |> preload(^@dataset_preload)
      |> Repo.get_by(datagouv_id: datagouv_id)

    if is_nil(dataset) do
      conn |> put_status(404) |> render(%{errors: "dataset not found"})
    else
      comp_fn = fn -> prepare_dataset_detail_data(dataset) end

      data =
        Transport.Cache.fetch("api-datasets-#{datagouv_id}", comp_fn, @by_id_cache_ttl)
        |> maybe_add_token_urls(conn)

      conn |> assign(:data, data) |> render()
    end
  end

  @spec geojson_by_id(Plug.Conn.t(), map) :: Plug.Conn.t()
  def geojson_by_id(%Plug.Conn{} = conn, %{"id" => id}) do
    Dataset
    |> Dataset.reject_experimental_datasets()
    |> Repo.get_by(datagouv_id: id)
    |> Repo.preload(declarative_spatial_areas: from(p in DB.AdministrativeDivision, select: [:nom, :type, :geom]))
    |> case do
      %Dataset{} = dataset ->
        data =
          dataset.declarative_spatial_areas
          |> DB.AdministrativeDivision.sorted()
          |> Enum.map(&to_feature(&1.geom, &1.nom))
          |> keep_valid_features()

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

  @spec transform_dataset(Dataset.t() | map()) :: map()
  defp transform_dataset(%Dataset{} = dataset),
    do: %{
      "datagouv_id" => dataset.datagouv_id,
      # to help discoverability, we explicitly add the datagouv_id as the id
      # (since it's used in /dataset/:id)
      "id" => dataset.datagouv_id,
      "title" => dataset.custom_title,
      "created_at" => dataset.created_at |> DateTime.to_date() |> Date.to_string(),
      "page_url" => TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, dataset.slug),
      "slug" => dataset.slug,
      "updated" => Helpers.last_updated(Dataset.official_resources(dataset)),
      "resources" => Enum.map(dataset.resources, &transform_resource/1),
      "community_resources" => Enum.map(Dataset.community_resources(dataset), &transform_resource/1),
      "covered_area" => covered_area(dataset),
      "legal_owners" => legal_owners(dataset),
      "type" => dataset.type,
      "licence" => dataset.licence,
      "publisher" => get_publisher(dataset),
      "tags" => dataset.custom_tags,
      "offers" => offers(dataset)
    }

  @spec get_publisher(Dataset.t()) :: map()
  defp get_publisher(dataset),
    do: %{
      "name" => dataset.organization,
      "id" => dataset.organization_id,
      "type" => "organization"
    }

  @spec transform_dataset_with_detail(Dataset.t() | map()) :: map()
  defp transform_dataset_with_detail(%Dataset{} = dataset) do
    dataset
    |> transform_dataset()
    |> add_conversions(dataset)
    |> Map.put(
      "history",
      Transport.History.Fetcher.history_resources(dataset,
        max_records: TransportWeb.DatasetView.max_nb_history_resources(),
        # see https://github.com/etalab/transport-site/issues/3324, not needed currently
        # in the API output
        preload_validations: false
      )
    )
  end

  # NOTE: only added in detailed dataset view
  defp add_conversions(%{"resources" => resources} = data, %Dataset{} = dataset) do
    conversions =
      dataset
      |> Dataset.get_resources_related_files()
      |> Enum.into(%{}, fn {resource_id, data} ->
        {resource_id,
         data
         |> Enum.reject(fn {_format, v} -> is_nil(v) end)
         |> Enum.into(%{}, fn {format, data} ->
           payload = %{
             filesize: Map.fetch!(data, :filesize),
             last_check_conversion_is_up_to_date: Map.fetch!(data, :resource_history_last_up_to_date_at),
             stable_url: Map.fetch!(data, :stable_url)
           }

           {format, payload}
         end)}
      end)

    Map.put(
      data,
      "resources",
      Enum.map(resources, fn %{"id" => resource_id} = resource ->
        Map.put(resource, "conversions", Map.fetch!(conversions, resource_id))
      end)
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

    latest_url =
      if use_download_url?(resource) do
        DB.Resource.download_url(resource)
      else
        resource.latest_url
      end

    %{
      "page_url" => TransportWeb.Router.Helpers.resource_url(TransportWeb.Endpoint, :details, resource.id),
      "id" => resource.id,
      "datagouv_id" => resource.datagouv_id,
      "title" => resource.title,
      "updated" => resource.last_update |> DateTime.to_iso8601(),
      "is_available" => resource.is_available,
      "url" => latest_url,
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

  defp use_download_url?(%DB.Resource{} = resource) do
    DB.Resource.pan_resource?(resource) or DB.Resource.served_by_proxy?(resource) or
      (DB.Dataset.has_custom_tag?(resource.dataset, "authentification_experimentation") and
         not DB.Resource.real_time?(resource))
  end

  @spec covered_area(DB.Dataset.t()) :: [map()]
  def covered_area(%DB.Dataset{declarative_spatial_areas: declarative_spatial_areas}) do
    declarative_spatial_areas
    |> DB.AdministrativeDivision.sorted()
    |> Enum.map(&Map.take(&1, [:type, :insee, :nom]))
  end

  defp legal_owners(dataset) do
    legal_owners_aom(dataset.legal_owners_aom) ++
      legal_owners_region(dataset.legal_owners_region) ++ legal_owners_company(dataset)
  end

  defp legal_owners_aom(aoms) do
    Enum.map(aoms, fn aom -> %{"name" => aom.nom, "siren" => aom.siren, "type" => "aom"} end)
  end

  defp legal_owners_region(regions) do
    Enum.map(regions, fn region -> %{"name" => region.nom, "insee" => region.insee, "type" => "region"} end)
  end

  def legal_owners_company(%{legal_owner_company_siren: nil}), do: []

  def legal_owners_company(%{legal_owner_company_siren: legal_owner_company_siren}) do
    [
      %{"id" => nil, "siren" => legal_owner_company_siren, "type" => "company"}
    ]
  end

  def offers(%DB.Dataset{} = dataset) do
    Enum.map(dataset.offers, &Map.take(&1, @offers_columns))
  end

  def prepare_datasets_index_data do
    # NOTE: week-end patch ; putting a heavy timeout to temporarily
    # work-around https://github.com/etalab/transport-site/issues/4598
    # which causes the whole API & backoffice to crash for hours.
    # On the next weekday, this query must be optimized :-)
    datasets_with_gtfs_metadata =
      DB.Dataset.base_query()
      |> DB.Dataset.join_from_dataset_to_metadata(
        Enum.map(Transport.ValidatorsSelection.validators_for_feature(:api_datasets_controller), & &1.validator_name())
      )
      |> preload([resource: r, resource_history: rh, multi_validation: mv, metadata: m, dataset: d],
        resources: {r, dataset: d, resource_history: {rh, validations: {mv, metadata: m}}}
      )
      |> Repo.all(timeout: 40_000)

    recent_limit = Transport.Jobs.GTFSRTMetadataJob.datetime_limit()

    datasets_with_gtfs_rt_metadata =
      DB.Dataset.base_query()
      |> DB.Resource.join_dataset_with_resource()
      |> DB.ResourceMetadata.join_resource_with_metadata()
      |> where([resource: r], r.format == "gtfs-rt")
      |> where([metadata: rm], rm.inserted_at > ^recent_limit)
      |> preload([resource: r, metadata: m, dataset: d], resources: {r, dataset: d, resource_metadata: m})
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

    %{}
    |> Dataset.list_datasets()
    |> Dataset.reject_experimental_datasets()
    |> preload(^@dataset_preload)
    |> Repo.all()
    |> Enum.map(fn dataset ->
      enriched_dataset = Map.get(existing_ids, dataset.id)
      add_enriched_resources_to_dataset(dataset, enriched_dataset)
    end)
    |> Enum.map(&transform_dataset(&1))
  end

  defp prepare_dataset_detail_data(%DB.Dataset{} = dataset) do
    gtfs_resources_with_metadata =
      DB.Resource.base_query()
      |> DB.ResourceHistory.join_resource_with_latest_resource_history()
      |> DB.MultiValidation.join_resource_history_with_latest_validation(
        Enum.map(Transport.ValidatorsSelection.validators_for_feature(:api_datasets_controller), & &1.validator_name())
      )
      |> DB.ResourceMetadata.join_validation_with_metadata()
      |> preload([resource_history: rh, multi_validation: mv, metadata: m],
        resource_history: {rh, validations: {mv, metadata: m}}
      )
      |> preload(:dataset)
      |> where([resource: r], r.dataset_id == ^dataset.id)
      |> select([resource: r], {r.id, r})
      |> DB.Repo.all()

    recent_limit = Transport.Jobs.GTFSRTMetadataJob.datetime_limit()

    gtfs_rt_resources_with_metadata =
      DB.Resource.base_query()
      |> DB.ResourceMetadata.join_resource_with_metadata()
      |> where([metadata: rm], rm.inserted_at > ^recent_limit)
      |> where([resource: r], r.dataset_id == ^dataset.id)
      |> preload([metadata: m], resource_metadata: m)
      |> preload(:dataset)
      |> select([resource: r], {r.id, r})
      |> DB.Repo.all()

    resources_with_metadata = Enum.into(gtfs_resources_with_metadata ++ gtfs_rt_resources_with_metadata, %{})

    enriched_resources =
      dataset
      |> Dataset.official_resources()
      |> Enum.map(fn r -> resources_with_metadata |> Map.get(r.id, r) end)

    dataset = dataset |> Map.put(:resources, enriched_resources)

    transform_dataset_with_detail(dataset)
  end

  defp log_request(%Plug.Conn{} = conn, _options) do
    controller = conn |> Phoenix.Controller.controller_module() |> to_string() |> String.trim_leading("Elixir.")

    token_id =
      case conn.assigns[:token] do
        %DB.Token{} = token -> token.id
        nil -> nil
      end

    Ecto.Changeset.change(%DB.APIRequest{}, %{
      time: DateTime.utc_now(),
      token_id: token_id,
      method: "#{controller}##{Phoenix.Controller.action_name(conn)}",
      path: conn.request_path
    })
    |> DB.Repo.insert!()

    conn
  end

  # Add a token to the `latest_url` for resources:
  # - published by the NAP organization.
  # - served by the NAP proxy.
  # - when the dataset has an experimentation tag.
  #
  # This is done at this stage to still be able to cache responses:
  # - an anonymous HTTP request will be served the cache
  # - an authenticated HTTP request with a token will get download URLs
  #   with the passed token
  defp maybe_add_token_urls(
         %{"resources" => resources} = dataset,
         %Plug.Conn{assigns: %{token: %DB.Token{secret: secret}}}
       ) do
    resources =
      Enum.map(resources, fn %{"url" => url} = resource ->
        is_download_url =
          url == TransportWeb.Router.Helpers.resource_url(TransportWeb.Endpoint, :download, resource["id"])

        if is_download_url or DB.Resource.served_by_proxy?(resource) do
          Map.put(resource, "url", url <> "?token=#{secret}")
        else
          resource
        end
      end)

    Map.put(dataset, "resources", resources)
  end

  defp maybe_add_token_urls(dataset, _conn), do: dataset
end
