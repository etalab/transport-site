defmodule DB.Dataset do
  @moduledoc """
  Dataset schema

  There's a trigger on update on postgres to update the search vector.
  There are also trigger on update on aom and region that will force an update on this model
  so the search vector is up-to-date.
  """
  alias DB.{AOM, Commune, DatasetGeographicView, LogsImport, NotificationSubscription, Region, Repo, Resource}
  alias Phoenix.HTML.Link
  import Ecto.{Changeset, Query}
  import TransportWeb.Gettext
  require Logger
  use Ecto.Schema
  use TypedEctoSchema

  @type conversion_details :: %{
          url: binary(),
          filesize: pos_integer(),
          resource_history_last_up_to_date_at: DateTime.t(),
          format: binary(),
          stable_url: binary()
        }

  @licences_ouvertes ["fr-lo", "lov2"]
  @licence_mobilités_tag "licence-mobilités"
  @hidden_dataset_custom_tag_value "masqué"

  typed_schema "dataset" do
    field(:datagouv_id, :string)
    field(:custom_title, :string)
    field(:created_at, :utc_datetime_usec)
    field(:description, :string)
    field(:frequency, :string)
    field(:last_update, :utc_datetime_usec)
    field(:licence, :string)
    field(:logo, :string)
    field(:full_logo, :string)
    field(:slug, :string)
    field(:tags, {:array, :string})
    field(:datagouv_title, :string)
    field(:type, :string)
    field(:organization, :string)
    field(:organization_type, :string)
    field(:has_realtime, :boolean)
    field(:is_active, :boolean)
    field(:is_hidden, :boolean)
    field(:population, :integer)
    field(:nb_reuses, :integer)
    field(:latest_data_gouv_comment_timestamp, :utc_datetime)
    field(:archived_at, :utc_datetime_usec)
    field(:custom_tags, {:array, :string}, default: [])
    # URLs for custom logos.
    # Currently we host custom logos in Cellar buckets.
    # See config: `:transport, :logos_bucket_url`
    field(:custom_logo, :string)
    field(:custom_full_logo, :string)
    field(:custom_logo_changed_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)

    # When the dataset is linked to some cities
    many_to_many(:communes, Commune, join_through: "dataset_communes", on_replace: :delete)

    many_to_many(:legal_owners_aom, AOM,
      join_through: "dataset_aom_legal_owner",
      on_replace: :delete
    )

    many_to_many(:legal_owners_region, Region,
      join_through: "dataset_region_legal_owner",
      on_replace: :delete
    )

    field(:legal_owner_company_siren, :string)

    has_many(:resources, Resource, on_replace: :delete, on_delete: :delete_all)
    has_many(:logs_import, LogsImport, on_replace: :delete, on_delete: :delete_all)
    has_many(:notification_subscriptions, NotificationSubscription, on_delete: :delete_all)

    # Deprecation notice: datasets won't be linked to region and aom like that in the future
    # ⬇️⬇️⬇️

    # A Dataset can be linked to *either*:
    # - a Region (and there is a special Region 'national' that represents the national datasets);
    # - an AOM;
    # - or a list of cities.
    belongs_to(:region, Region)
    belongs_to(:aom, AOM)
    belongs_to(:organization_object, DB.Organization, foreign_key: :organization_id, type: :string, on_replace: :nilify)

    # we ask in the backoffice for a name to display
    # (used in the long title of a dataset and to find the associated datasets)
    field(:associated_territory_name, :string)

    field(:search_payload, :map)
    many_to_many(:followers, DB.Contact, join_through: "dataset_followers", on_replace: :delete)
  end

  def base_query do
    from(d in DB.Dataset, as: :dataset, where: d.is_active and not d.is_hidden)
  end

  def all_datasets, do: from(d in DB.Dataset, as: :dataset)
  def archived, do: base_query() |> where([dataset: d], not is_nil(d.archived_at))
  def inactive, do: from(d in DB.Dataset, as: :dataset, where: not d.is_active)
  def hidden, do: from(d in DB.Dataset, as: :dataset, where: d.is_active and d.is_hidden)
  def include_hidden_datasets(%Ecto.Query{} = query), do: or_where(query, [dataset: d], d.is_hidden)
  def base_with_hidden_datasets, do: base_query() |> include_hidden_datasets()

  @spec archived?(__MODULE__.t()) :: boolean()
  def archived?(%__MODULE__{archived_at: nil}), do: false
  def archived?(%__MODULE__{archived_at: %DateTime{}}), do: true

  @spec active?(__MODULE__.t()) :: boolean()
  def active?(%__MODULE__{is_active: is_active}), do: is_active

  @doc """
  Creates a query with the following inner joins:
  datasets <> Resource <> ResourceHistory <> MultiValidation <> ResourceMetadata
  """
  def join_from_dataset_to_metadata(query, validator_name) do
    query
    |> DB.Resource.join_dataset_with_resource()
    |> DB.ResourceHistory.join_resource_with_latest_resource_history()
    |> DB.MultiValidation.join_resource_history_with_latest_validation(validator_name)
    |> DB.ResourceMetadata.join_validation_with_metadata()
  end

  @doc """
  Returns a list of resources, with their last resource_history preloaded
  """
  def last_resource_history(dataset_id) do
    DB.Dataset.all_datasets()
    |> where([dataset: d], d.id == ^dataset_id)
    |> join(:left, [dataset: d], r in DB.Resource, on: d.id == r.dataset_id, as: :resource)
    |> join(:left, [resource: r], rh in DB.ResourceHistory,
      on: rh.resource_id == r.id,
      as: :resource_history
    )
    |> distinct([resource: r], r.id)
    |> order_by([resource: r, resource_history: rh],
      asc: r.id,
      desc: rh.inserted_at
    )
    |> preload([resource: r, resource_history: rh], resources: {r, resource_history: rh})
    |> DB.Repo.one!()
    |> Map.get(:resources, [])
  end

  @spec type_to_str_map() :: %{binary() => binary()}
  def type_to_str_map,
    do: %{
      "public-transit" => dgettext("db-dataset", "Public transit - static schedules"),
      "carpooling-areas" => dgettext("db-dataset", "Carpooling areas"),
      "carpooling-lines" => dgettext("db-dataset", "Carpooling lines"),
      "carpooling-offers" => dgettext("db-dataset", "Carpooling offers"),
      "charging-stations" => dgettext("db-dataset", "Charging & refuelling stations"),
      "air-transport" => dgettext("db-dataset", "Air transport"),
      "bike-scooter-sharing" => dgettext("db-dataset", "Bike and scooter sharing"),
      "car-motorbike-sharing" => dgettext("db-dataset", "Car and motorbike sharing"),
      "road-data" => dgettext("db-dataset", "Road data"),
      "locations" => dgettext("db-dataset", "Mobility locations"),
      "informations" => dgettext("db-dataset", "Other informations"),
      "private-parking" => dgettext("db-dataset", "Private parking"),
      "bike-way" => dgettext("db-dataset", "Bike networks"),
      "bike-parking" => dgettext("db-dataset", "Bike parking"),
      "low-emission-zones" => dgettext("db-dataset", "Low emission zones"),
      "transport-traffic" => dgettext("db-dataset", "Transport traffic")
    }

  @spec type_to_str(binary()) :: binary()
  def type_to_str(type), do: type_to_str_map()[type]

  @spec types() :: [binary()]
  def types, do: Map.keys(type_to_str_map())

  @spec no_validations_query() :: Ecto.Query.t()
  defp no_validations_query do
    from(r in Resource,
      select: %Resource{
        format: r.format,
        title: r.title,
        url: r.url,
        id: r.id,
        dataset_id: r.dataset_id,
        datagouv_id: r.datagouv_id,
        last_update: r.last_update,
        latest_url: r.latest_url,
        is_community_resource: r.is_community_resource,
        is_available: r.is_available,
        description: r.description,
        community_resource_publisher: r.community_resource_publisher,
        original_resource_url: r.original_resource_url,
        schema_name: r.schema_name,
        schema_version: r.schema_version,
        type: r.type,
        display_position: r.display_position
      }
    )
  end

  @spec preload_without_validations() :: Ecto.Query.t()
  defp preload_without_validations do
    s = no_validations_query()
    __MODULE__ |> preload(resources: ^s)
  end

  @spec preload_without_validations(Ecto.Query.t()) :: Ecto.Query.t()
  defp preload_without_validations(query) do
    s = no_validations_query()
    query |> preload(resources: ^s)
  end

  @spec filter_by_fulltext(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_fulltext(query, %{"q" => ""}), do: query

  defp filter_by_fulltext(query, %{"q" => q}) do
    where(
      query,
      [d],
      fragment("search_vector @@ plainto_tsquery('custom_french', ?) or unaccent(datagouv_title) = unaccent(?)", ^q, ^q)
    )
  end

  defp filter_by_fulltext(query, _), do: query

  @spec filter_by_region(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_region(query, %{"region" => region_id}) do
    query
    |> join(:right, [d], d_geo in DatasetGeographicView, on: d.id == d_geo.dataset_id)
    |> where([d, d_geo], d_geo.region_id == ^region_id)
  end

  defp filter_by_region(query, _), do: query

  @spec filter_by_category(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_category(query, %{"filter" => filter_key}) do
    case filter_key do
      "has_realtime" -> where(query, [d], d.has_realtime == true)
      "urban_public_transport" -> where(query, [d], not is_nil(d.aom_id) and d.type == "public-transit")
      _ -> query
    end
  end

  defp filter_by_category(query, _), do: query

  @spec filter_by_climate_resilience_bill(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_climate_resilience_bill(%Ecto.Query{} = query, %{"loi-climat-resilience" => "true"}) do
    filter_by_custom_tag(query, %{"custom_tag" => "loi-climat-resilience"})
  end

  defp filter_by_climate_resilience_bill(%Ecto.Query{} = query, _), do: query

  @spec filter_by_custom_tag(Ecto.Query.t(), binary() | map()) :: Ecto.Query.t()
  def filter_by_custom_tag(%Ecto.Query{} = query, custom_tag) when is_binary(custom_tag) do
    where(query, [dataset: d], ^custom_tag in d.custom_tags)
  end

  def filter_by_custom_tag(%Ecto.Query{} = query, %{"custom_tag" => custom_tag}),
    do: filter_by_custom_tag(query, custom_tag)

  def filter_by_custom_tag(%Ecto.Query{} = query, _), do: query

  @spec filter_by_feature(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_feature(query, %{"features" => [feature]})
       when feature in ["service_alerts", "trip_updates", "vehicle_positions"] do
    recent_limit = Transport.Jobs.GTFSRTMetadataJob.datetime_limit()

    query
    |> join(:inner, [dataset: d], r in DB.Resource, on: r.dataset_id == d.id, as: :resource)
    |> join(
      :inner,
      [resource: r],
      rm in DB.ResourceMetadata,
      on:
        rm.resource_id == r.id and
          fragment(
            "? = ANY (?)",
            ^feature,
            rm.features
          ) and
          rm.inserted_at > ^recent_limit
    )
  end

  defp filter_by_feature(query, %{"features" => feature}) do
    # Note: @> is the 'contains' operator
    query
    |> DB.ResourceHistory.join_dataset_with_latest_resource_history()
    |> DB.MultiValidation.join_resource_history_with_latest_validation(
      Transport.Validators.GTFSTransport.validator_name()
    )
    |> DB.ResourceMetadata.join_validation_with_metadata()
    |> where([metadata: rm], fragment("? @> ?::varchar[]", rm.features, ^feature))
  end

  defp filter_by_feature(query, _), do: query

  @spec filter_by_mode(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_mode(query, %{"modes" => modes}) when is_list(modes) do
    query
    # Using specific jointure name: if piping with filter_by_feature it will not conflict
    |> join(:inner, [dataset: d], r in assoc(d, :resources), as: :resource_for_mode)
    |> where([resource_for_mode: r], fragment("?->'gtfs_modes' @> ?", r.counter_cache, ^modes))
  end

  defp filter_by_mode(query, _), do: query

  @spec filter_by_type(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_type(query, %{"type" => type}), do: where(query, [d], d.type == ^type)
  defp filter_by_type(query, _), do: query

  @spec filter_by_aom(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_aom(query, %{"aom" => aom_id}) do
    query
    |> join(:left, [dataset: d], aom in assoc(d, :legal_owners_aom), on: aom.id == ^aom_id, as: :aom)
    |> where([dataset: d, aom: aom], d.aom_id == ^aom_id or aom.id == ^aom_id)
  end

  defp filter_by_aom(query, _), do: query

  @spec filter_by_commune(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_commune(query, %{"insee_commune" => commune_insee}) do
    # return the datasets available for a city.
    # This dataset can either be linked to a city or to an AOM/region covering this city
    query
    |> where(
      [d],
      fragment(
        """
        (
          ? IN (
              (
                SELECT DISTINCT dc.dataset_id FROM dataset_communes AS dc
                JOIN commune ON commune.id = dc.commune_id
                WHERE commune.insee = ?
              )
              UNION
              (
                SELECT dataset.id FROM dataset
                JOIN aom ON aom.id = dataset.aom_id
                JOIN commune ON commune.aom_res_id = aom.composition_res_id
                WHERE commune.insee = ?
              )
              UNION
              (
                SELECT dataset.id FROM dataset
                JOIN region ON region.id = dataset.region_id
                JOIN commune ON commune.region_id = region.id
                WHERE commune.insee = ?
              )
            )
        )
        """,
        d.id,
        ^commune_insee,
        ^commune_insee,
        ^commune_insee
      )
    )
  end

  defp filter_by_commune(query, _), do: query

  @spec filter_by_licence(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_licence(query, %{"licence" => "licence-ouverte"}),
    do: where(query, [d], d.licence in @licences_ouvertes)

  defp filter_by_licence(query, %{"licence" => licence}), do: where(query, [d], d.licence == ^licence)
  defp filter_by_licence(query, _), do: query

  @spec filter_by_organization(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_organization(query, %{"organization_id" => organization_id}) do
    where(query, [d], d.organization_id == ^organization_id)
  end

  defp filter_by_organization(query, _), do: query

  @spec list_datasets(map()) :: Ecto.Query.t()
  def list_datasets(%{} = params) do
    params
    |> list_datasets_no_order()
    |> order_datasets(params)
  end

  @spec list_datasets_no_order(map()) :: Ecto.Query.t()
  def list_datasets_no_order(%{} = params) do
    q =
      base_query()
      |> distinct([dataset: d], d.id)
      |> filter_by_region(params)
      |> filter_by_feature(params)
      |> filter_by_mode(params)
      |> filter_by_category(params)
      |> filter_by_type(params)
      |> filter_by_aom(params)
      |> filter_by_commune(params)
      |> filter_by_licence(params)
      |> filter_by_climate_resilience_bill(params)
      |> filter_by_custom_tag(params)
      |> filter_by_organization(params)
      |> filter_by_fulltext(params)
      |> select([dataset: d], d.id)

    base_query()
    |> where([dataset: d], d.id in subquery(q))
    |> preload_without_validations()
  end

  @spec order_datasets(Ecto.Query.t(), map()) :: Ecto.Query.t()
  def order_datasets(datasets, %{"order_by" => "alpha"}), do: order_by(datasets, asc: :custom_title)
  def order_datasets(datasets, %{"order_by" => "most_recent"}), do: order_by(datasets, desc: :created_at)

  def order_datasets(datasets, %{"q" => q}),
    do:
      order_by(datasets,
        desc: fragment("ts_rank_cd(search_vector, plainto_tsquery('custom_french', ?), 32) DESC, population", ^q),
        asc: :custom_title
      )

  def order_datasets(datasets, %{"region" => region_id}) do
    case Integer.parse(region_id) do
      {region_id, ""} ->
        order_by(datasets,
          desc: fragment("case when region_id = ? then 1 else 0 end", ^region_id),
          desc: fragment("coalesce(population, 0)"),
          asc: :custom_title
        )

      :error ->
        datasets
    end
  end

  def order_datasets(datasets, %{"aom" => aom_id}) do
    aom_id = String.to_integer(aom_id)

    order_by(datasets,
      desc: fragment("case when aom_id = ? then 1 else 0 end", ^aom_id),
      desc: fragment("coalesce(population, 0)"),
      asc: :custom_title
    )
  end

  def order_datasets(datasets, %{"insee_commune" => _insee_commune}) do
    order_by(datasets,
      # priority to non regional datasets when we search for a commune
      desc: fragment("case when region_id is null then 1 else 0 end"),
      asc: :custom_title
    )
  end

  def order_datasets(datasets, _params) do
    pan_publisher = Application.fetch_env!(:transport, :datagouvfr_transport_publisher_id)

    order_by(datasets,
      desc:
        fragment(
          "case when organization_id = ? and custom_title ilike 'base nationale%' then 1 else 0 end",
          ^pan_publisher
        ),
      # Gotcha, population can be null for datasets covering France/Europe
      # https://github.com/etalab/transport-site/issues/3848
      desc: fragment("coalesce(population, 100000000)"),
      asc: :custom_title
    )
  end

  @spec changeset(map()) :: {:error, binary()} | {:ok, Ecto.Changeset.t()}
  def changeset(params = %{}) when is_map_key(params, "datagouv_id") or is_map_key(params, "dataset_id") do
    dataset =
      __MODULE__
      |> preload([:legal_owners_aom, :legal_owners_region])
      |> get_dataset(params)
      |> case do
        nil -> %__MODULE__{}
        dataset -> dataset
      end

    apply_changeset(dataset, params)
  end

  def changeset(_) do
    {:error, "datagouv_id or dataset_id are required"}
  end

  # this case is used to update a dataset slug from backoffice without changing the dataset_id
  # useful when the dataset has been deleted / recreated on data.gouv.fr but we want to keep the resources history
  def get_dataset(query, %{"dataset_id" => dataset_id}) do
    query |> Repo.get(dataset_id)
  end

  def get_dataset(query, %{"datagouv_id" => datagouv_id}) when is_binary(datagouv_id) do
    query |> Repo.get_by(datagouv_id: datagouv_id)
  end

  defp apply_changeset(%__MODULE__{} = dataset, params) do
    territory_name = Map.get(params, "associated_territory_name") || dataset.associated_territory_name

    legal_owners_aom = get_legal_owners_aom(dataset, params)
    legal_owners_region = get_legal_owners_region(dataset, params)

    dataset
    |> Repo.preload([:resources, :communes, :region, :legal_owners_aom, :legal_owners_region, :organization_object])
    |> cast(params, [
      :datagouv_id,
      :custom_title,
      :created_at,
      :description,
      :frequency,
      :organization_type,
      :last_update,
      :licence,
      :logo,
      :full_logo,
      :slug,
      :tags,
      :datagouv_title,
      :type,
      :region_id,
      :nb_reuses,
      :is_active,
      :associated_territory_name,
      :latest_data_gouv_comment_timestamp,
      :archived_at,
      :custom_tags,
      :legal_owner_company_siren,
      :custom_logo,
      :custom_full_logo,
      :custom_logo_changed_at
    ])
    |> update_change(:custom_title, &String.trim/1)
    |> cast_aom(params)
    |> cast_datagouv_zone(params, territory_name)
    |> cast_nation_dataset(params)
    |> cast_assoc(:resources)
    |> validate_required([:slug])
    |> validate_siren()
    |> validate_territory_mutual_exclusion()
    |> maybe_overwrite_licence()
    |> has_real_time()
    |> set_is_hidden()
    |> validate_organization_type()
    |> add_organization(params)
    |> maybe_set_custom_logo_changed_at()
    |> put_assoc(:legal_owners_aom, legal_owners_aom)
    |> put_assoc(:legal_owners_region, legal_owners_region)
    |> case do
      %{valid?: false, changes: changes} = changeset when changes == %{} ->
        {:ok, %{changeset | action: :ignore}}

      %{valid?: true} = changeset ->
        {:ok, changeset}

      %{valid?: false} = errors ->
        Logger.warning("error while importing dataset: #{format_error(errors)}")
        {:error, format_error(errors)}
    end
  end

  defp add_organization(%Ecto.Changeset{} = changeset, %{"organization" => %{"id" => id, "name" => name} = org}) do
    changeset
    |> put_assoc(
      :organization_object,
      DB.Organization.changeset(DB.Repo.get(DB.Organization, id) || %DB.Organization{}, org)
    )
    |> put_change(:organization, name)
  end

  defp add_organization(%Ecto.Changeset{} = changeset, _), do: changeset

  defp maybe_set_custom_logo_changed_at(%Ecto.Changeset{} = changeset) do
    if changed?(changeset, :custom_logo) do
      put_change(changeset, :custom_logo_changed_at, DateTime.utc_now())
    else
      changeset
    end
  end

  defp get_legal_owners_aom(dataset, params) do
    case params["legal_owners_aom"] do
      nil ->
        if Ecto.assoc_loaded?(dataset.legal_owners_aom) do
          # get existing aom legal owners
          dataset.legal_owners_aom
        else
          # new dataset
          []
        end

      # aom legal owners are updated from the params
      legal_owners_aom_id ->
        Repo.all(from(aom in AOM, where: aom.id in ^legal_owners_aom_id))
    end
  end

  defp get_legal_owners_region(dataset, params) do
    case params["legal_owners_region"] do
      nil ->
        if Ecto.assoc_loaded?(dataset.legal_owners_region) do
          dataset.legal_owners_region
        else
          []
        end

      legal_owners_region_id ->
        Repo.all(from(region in Region, where: region.id in ^legal_owners_region_id))
    end
  end

  @spec format_error(any()) :: binary()
  defp format_error(changeset), do: "#{inspect(Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end))}"

  @spec link_to_datagouv(DB.Dataset.t()) :: any()
  def link_to_datagouv(%__MODULE__{} = dataset) do
    Link.link(
      dgettext("db-dataset", "See on data.gouv.fr"),
      to: datagouv_url(dataset),
      role: "link",
      target: "_blank"
    )
  end

  @spec datagouv_url(DB.Dataset.t()) :: binary()
  def datagouv_url(%__MODULE__{slug: slug}) do
    Path.join([Application.fetch_env!(:transport, :datagouvfr_site), "datasets", slug])
  end

  @spec count_by_mode(binary()) :: number()
  def count_by_mode(tag) do
    base_query()
    |> join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
    |> where([metadata: m], ^tag in m.modes)
    |> distinct([dataset: d], d.id)
    |> Repo.aggregate(:count, :id)
  end

  @spec count_coach() :: number()
  def count_coach do
    base_query()
    |> join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
    # 14 is the national "region". It means that it is not bound to a region or local territory
    |> where([metadata: m, dataset: d], d.region_id == 14 and "bus" in m.modes)
    |> distinct([dataset: d], d.id)
    |> Repo.aggregate(:count, :id)
  end

  @spec count_by_type(binary()) :: any()
  def count_by_type(type) do
    base_query()
    |> where([d], d.type == ^type)
    |> Repo.aggregate(:count, :id)
  end

  @spec count_by_type :: map
  def count_by_type, do: for(type <- __MODULE__.types(), into: %{}, do: {type, count_by_type(type)})

  @spec count_public_transport_has_realtime :: number()
  def count_public_transport_has_realtime do
    base_query()
    |> where([d], d.has_realtime and d.type == "public-transit")
    |> Repo.aggregate(:count, :id)
  end

  @spec count_by_custom_tag(binary()) :: non_neg_integer()
  def count_by_custom_tag(custom_tag) do
    base_query() |> filter_by_custom_tag(custom_tag) |> Repo.aggregate(:count, :id)
  end

  @spec get_by_slug(binary) :: {:ok, __MODULE__.t()} | {:error, binary()}
  def get_by_slug(slug) do
    preload_without_validations()
    |> where(slug: ^slug)
    |> preload([:region, :aom, :communes, resources: [:resources_related, :dataset]])
    |> Repo.one()
    |> case do
      nil -> {:error, "Dataset with slug #{slug} not found"}
      dataset -> {:ok, dataset}
    end
  end

  @spec get_other_datasets(__MODULE__.t()) :: [__MODULE__.t()]
  def get_other_datasets(%__MODULE__{id: id, aom_id: aom_id}) when not is_nil(aom_id) do
    __MODULE__.base_query()
    |> where([d], d.id != ^id)
    |> where([d], d.aom_id == ^aom_id)
    |> Repo.all()
  end

  def get_other_datasets(%__MODULE__{id: id, region_id: region_id}) when not is_nil(region_id) do
    __MODULE__.base_query()
    |> where([d], d.id != ^id)
    |> where([d], d.region_id == ^region_id)
    |> Repo.all()
  end

  # for the datasets linked to multiple cities we use the
  # backoffice filled field 'associated_territory_name'
  # to get the other_datasets
  # This way we can control which datasets to link to
  def get_other_datasets(%__MODULE__{id: id, associated_territory_name: associated_territory_name}) do
    __MODULE__.base_query()
    |> where([d], d.id != ^id)
    |> where([d], d.associated_territory_name == ^associated_territory_name)
    |> Repo.all()
  end

  def get_other_dataset(_), do: []

  @spec get_territory(__MODULE__.t()) :: {:ok, binary()} | {:error, binary()}
  def get_territory(%__MODULE__{aom: %{nom: nom}}), do: {:ok, nom}

  def get_territory(%__MODULE__{aom_id: aom_id}) when not is_nil(aom_id) do
    case Repo.get(AOM, aom_id) do
      nil -> {:error, "Could not find territory of AOM with id #{aom_id}"}
      aom -> {:ok, aom.nom}
    end
  end

  def get_territory(%__MODULE__{region: %{nom: nom}}), do: {:ok, nom}

  def get_territory(%__MODULE__{region_id: region_id}) when not is_nil(region_id) do
    case Repo.get(Region, region_id) do
      nil -> {:error, "Could not find territory of Region with id #{region_id}"}
      region -> {:ok, region.nom}
    end
  end

  def get_territory(%__MODULE__{associated_territory_name: associated_territory_name}),
    do: {:ok, associated_territory_name}

  def get_territory(_), do: {:error, "Trying to find the territory of an unkown entity"}

  @spec get_territory_or_nil(__MODULE__.t()) :: binary() | nil
  def get_territory_or_nil(%__MODULE__{} = d) do
    case get_territory(d) do
      {:ok, t} -> t
      _ -> nil
    end
  end

  @spec get_covered_area_names(__MODULE__.t()) :: binary | [any]
  def get_covered_area_names(%__MODULE__{aom_id: aom_id}) when not is_nil(aom_id) do
    get_covered_area_names(
      "select string_agg(nom, ', ' ORDER BY nom) from commune group by aom_res_id having aom_res_id = (select composition_res_id from aom where id = $1)",
      aom_id
    )
  end

  def get_covered_area_names(%__MODULE__{region_id: region_id}) when not is_nil(region_id) do
    get_covered_area_names(
      "select string_agg(distinct(departement), ', ') from aom where region_id = $1",
      region_id
    )
  end

  def get_covered_area_names(%__MODULE__{communes: communes}) when length(communes) != 0 do
    communes
    |> Enum.map(fn c -> c.nom end)
    # credo:disable-for-next-line
    |> Enum.join(", ")
  end

  def get_covered_area_names(_), do: "National"

  @spec get_covered_area_names(binary, binary()) :: [binary()]
  def get_covered_area_names(query, id) do
    query
    |> Repo.query([id])
    |> case do
      {:ok, %{rows: [names | _]}} ->
        Enum.reject(names, &(&1 == nil))

      {:ok, %{rows: []}} ->
        ""

      {:error, error} ->
        Logger.error(error)
        ""
    end
  end

  @spec official_resources(__MODULE__.t()) :: list(Resource.t())
  def official_resources(%__MODULE__{resources: resources}),
    do: resources |> Stream.reject(&DB.Resource.community_resource?/1) |> Enum.to_list()

  def official_resources(%__MODULE__{}), do: []

  @spec community_resources(__MODULE__.t()) :: list(Resource.t())
  def community_resources(%__MODULE__{resources: resources}),
    do: resources |> Stream.filter(&DB.Resource.community_resource?/1) |> Enum.to_list()

  def community_resources(%__MODULE__{}), do: []

  @spec formats(__MODULE__.t()) :: [binary]
  def formats(%__MODULE__{} = dataset) do
    dataset
    |> official_resources()
    |> Enum.map(& &1.format)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
    |> Enum.dedup()
  end

  def formats(_), do: []

  @spec validate(binary | integer | __MODULE__.t()) :: {:error, String.t()} | {:ok, nil}
  @spec validate(binary | integer | __MODULE__.t(), force_validation: boolean()) :: {:error, String.t()} | {:ok, nil}
  def validate(d), do: validate(d, force_validation: false)

  def validate(%__MODULE__{id: id}, opt), do: validate(id, opt)

  def validate(id, opt) when is_binary(id), do: id |> String.to_integer() |> validate(opt)

  def validate(id, opt) when is_integer(id) do
    force_validation = Keyword.get(opt, :force_validation, false)
    dataset = __MODULE__ |> Repo.get!(id) |> Repo.preload(:resources)

    {real_time_resources, static_resources} =
      dataset
      |> official_resources()
      |> Enum.split_with(&Resource.real_time?/1)

    # unique period is set to nil, to force the resource history job to be executed
    static_resources
    |> Enum.map(
      &Transport.Jobs.ResourceHistoryJob.historize_and_validate_job(%{resource_id: &1.id},
        history_options: [unique: nil],
        validation_custom_args: %{"force_validation" => force_validation}
      )
    )
    |> Oban.insert_all()

    # Oban.insert_all does not enforce `unique` params
    # https://hexdocs.pm/oban/Oban.html#insert_all/3
    # This is something we rely on to force the job execution
    real_time_resources
    |> Enum.map(&Transport.Jobs.ResourceValidationJob.new(%{"resource_id" => &1.id}))
    |> Oban.insert_all()

    {:ok, nil}
  end

  @doc """
  Find datasets present on the NAP for which the user is a member of the organization.
  """
  @spec datasets_for_user(Plug.Conn.t() | OAuth2.AccessToken.t()) :: [__MODULE__.t()] | {:error, OAuth2.Error.t()}
  def datasets_for_user(conn_or_token) do
    case Datagouvfr.Client.User.Wrapper.impl().me(conn_or_token) do
      {:ok, %{"organizations" => organizations}} ->
        organization_ids = Enum.map(organizations, fn %{"id" => id} -> id end)

        __MODULE__.base_query()
        |> preload(:resources)
        |> where([dataset: d], d.organization_id in ^organization_ids)
        |> Repo.all()

      error ->
        error
    end
  end

  @spec get_resources_related_files(any()) :: %{integer() => %{optional(atom()) => conversion_details() | nil}}
  def get_resources_related_files(%__MODULE__{resources: resources} = dataset) when is_list(resources) do
    target_formats = target_conversion_formats(dataset)
    # The filler's purpose is to make sure we have a {conversion_format, nil} value
    # for every resource, even if we don't have a conversion
    filler = Enum.into(available_conversion_formats(), %{}, &{&1, nil})
    resource_ids = Enum.map(resources, & &1.id)

    results =
      DB.Resource.base_query()
      |> where([resource: r], r.id in ^resource_ids)
      |> DB.ResourceHistory.join_resource_with_latest_resource_history()
      |> DB.DataConversion.join_resource_history_with_data_conversion(target_formats)
      |> select(
        [resource: r, resource_history: rh, data_conversion: dc],
        {r.id,
         {dc.convert_to,
          %{
            url: fragment("? ->> 'permanent_url'", dc.payload),
            filesize: fragment("(? ->> 'filesize')::int", dc.payload),
            # Using `fragment` to avoid `convert_to` being cast to atoms
            format: fragment("?", dc.convert_to),
            resource_history_last_up_to_date_at: rh.last_up_to_date_at
          }}}
      )
      |> Repo.all()
      # transform from
      # [{id1, {:GeoJSON, %{infos}}}, {id1, {:NeTEx, %{infos}}}, {id2, {:NeTEx, %{infos}}}]
      # to
      # %{id1 => %{:GeoJSON: %{infos}, :NeTEx: %{infos}}, id2 => %{:GeoJSON: nil, :NeTEx: %{infos}}}
      |> Enum.group_by(fn {id, _} -> id end, fn {resource_id, {format, data}} ->
        stable_url = TransportWeb.Router.Helpers.conversion_url(TransportWeb.Endpoint, :get, resource_id, format)
        {format, Map.put(data, :stable_url, stable_url)}
      end)
      |> Enum.into(%{}, fn {id, l} -> {id, Map.merge(filler, Enum.into(l, %{}))} end)

    empty_results = Enum.into(resource_ids, %{}, fn id -> {id, filler} end)

    Map.merge(empty_results, results)
  end

  def get_resources_related_files(_), do: %{}

  @doc """
  The list of conversion formats we are interested in for a dataset.

  Possible formats are handled by `DB.DataConversion`.
  If the dataset contains at least a NeTEx resource, we are not interested in NeTEx conversions
  UNLESS the dataset has a custom tag `keep_netex_conversions` we added ourselves.

  iex> target_conversion_formats(%DB.Dataset{resources: [%DB.Resource{format: "gtfs"}]})
  [:GeoJSON, :NeTEx]
  iex> target_conversion_formats(%DB.Dataset{resources: [%DB.Resource{format: "gtfs"}, %DB.Resource{format: "NeTEx"}]})
  [:GeoJSON]
  iex> target_conversion_formats(%DB.Dataset{resources: [%DB.Resource{format: "gtfs"}, %DB.Resource{format: "NeTEx"}]})
  [:GeoJSON]
  """
  @spec target_conversion_formats(DB.Dataset.t()) :: [atom()]
  def target_conversion_formats(%__MODULE__{resources: resources} = dataset) when is_list(resources) do
    keep_netex_conversions = has_custom_tag?(dataset, "keep_netex_conversions")
    has_netex = Enum.any?(resources, &DB.Resource.netex?/1)

    if has_netex and not keep_netex_conversions do
      Enum.reject(available_conversion_formats(), &(&1 == :NeTEx))
    else
      available_conversion_formats()
    end
  end

  defp available_conversion_formats, do: Ecto.Enum.values(DB.DataConversion, :convert_to)

  defp validate_siren(%Ecto.Changeset{} = changeset) do
    case get_change(changeset, :legal_owner_company_siren) do
      nil ->
        changeset

      siren ->
        if Transport.Companies.is_valid_siren?(siren) do
          changeset
        else
          add_error(changeset, :legal_owner_company_siren, "SIREN is not valid")
        end
    end
  end

  @spec validate_territory_mutual_exclusion(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_territory_mutual_exclusion(changeset) do
    has_cities =
      changeset
      |> get_field(:communes)
      |> length
      |> Kernel.min(1)

    other_fields =
      [:region_id, :aom_id]
      |> Enum.map(fn f -> get_field(changeset, f) end)
      |> Enum.count(fn f -> f not in ["", nil] end)

    fields = other_fields + has_cities

    case fields do
      1 ->
        changeset

      _ ->
        add_error(
          changeset,
          :region,
          dgettext("db-dataset", "You need to fill either aom, region or use datagouv's zone")
        )
    end
  end

  @spec validate_organization_type(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_organization_type(changeset) do
    changeset
    |> get_field(:organization_type)
    # allow a nil value for the moment
    |> Kernel.in(TransportWeb.EditDatasetLive.organization_types() ++ [nil])
    |> case do
      true -> changeset
      false -> changeset |> add_error(:organization_type, dgettext("db-dataset", "Organization type is invalid"))
    end
  end

  @spec cast_aom(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  defp cast_aom(changeset, %{"insee" => insee}) when insee in [nil, ""], do: change(changeset, aom_id: nil)

  defp cast_aom(changeset, %{"insee" => insee}) do
    Commune
    |> preload([:aom_res])
    |> Repo.get_by(insee: insee)
    |> case do
      nil ->
        add_error(changeset, :aom_id, dgettext("db-dataset", "Unable to find INSEE code '%{insee}'", insee: insee))

      commune ->
        case commune.aom_res do
          nil ->
            add_error(
              changeset,
              :aom_id,
              dgettext("db-dataset", "INSEE code '%{insee}' not associated with an AOM", insee: insee)
            )

          aom_res ->
            change(changeset, aom_id: aom_res.id)
        end
    end
  end

  defp cast_aom(changeset, _), do: changeset

  @spec cast_nation_dataset(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  defp cast_nation_dataset(changeset, %{"national_dataset" => "true"}) do
    if is_nil(get_field(changeset, :region_id)) do
      national =
        Region
        |> where([r], r.nom == "National")
        |> Repo.one!()

      put_change(changeset, :region_id, national.id)
    else
      add_error(changeset, :region, dgettext("db-dataset", "A dataset cannot be national and regional"))
    end
  end

  defp cast_nation_dataset(changeset, _), do: changeset

  @spec cast_datagouv_zone(Ecto.Changeset.t(), map(), binary()) :: Ecto.Changeset.t()
  defp cast_datagouv_zone(changeset, _, nil) do
    changeset
    |> put_assoc(:communes, [])
  end

  defp cast_datagouv_zone(changeset, _, "") do
    changeset
    |> put_assoc(:communes, [])
  end

  # We’ll only cast datagouv zone if there is something written in the associated territory name in the backoffice
  defp cast_datagouv_zone(changeset, %{"zones" => zones_insee}, _associated_territory_name) do
    communes =
      Commune
      |> where([c], c.insee in ^zones_insee)
      |> Repo.all()

    changeset
    |> put_assoc(:communes, communes)
  end

  defp maybe_overwrite_licence(%Ecto.Changeset{} = changeset) do
    custom_tags = get_field(changeset, :custom_tags) || []

    if @licence_mobilités_tag in custom_tags do
      changeset |> change(licence: "mobility-licence")
    else
      changeset
    end
  end

  defp has_real_time(changeset) do
    has_realtime = changeset |> get_field(:resources) |> Enum.any?(&Resource.real_time?/1)
    changeset |> change(has_realtime: has_realtime)
  end

  defp set_is_hidden(%Ecto.Changeset{} = changeset) do
    is_hidden =
      has_custom_tag?(%__MODULE__{custom_tags: get_field(changeset, :custom_tags)}, @hidden_dataset_custom_tag_value)

    change(changeset, is_hidden: is_hidden)
  end

  @spec resources_content_updated_at(__MODULE__.t()) :: map()
  def resources_content_updated_at(%__MODULE__{id: dataset_id}) do
    DB.Resource
    |> join(:left, [r], rh in DB.ResourceHistory, on: rh.resource_id == r.id)
    |> where([r], r.dataset_id == ^dataset_id)
    |> group_by([r, rh], [r.id, rh.resource_id])
    |> select([r, rh], {r.id, count(rh.id), max(fragment("payload ->>'download_datetime'"))})
    |> DB.Repo.all()
    |> Enum.map(fn {id, count, updated_at} ->
      case count do
        n when n in [0, 1] ->
          {id, nil}

        _ ->
          {:ok, datetime_updated_at, 0} = updated_at |> DateTime.from_iso8601()
          {id, datetime_updated_at}
      end
    end)
    |> Enum.into(%{})
  end

  @doc """
  Should this dataset not be historicized?

  iex> should_skip_history?(%DB.Dataset{type: "road-data"})
  true
  iex> should_skip_history?(%DB.Dataset{type: "public-transit"})
  false
  iex> should_skip_history?(%DB.Dataset{type: "public-transit", custom_tags: ["skip_history", "foo"]})
  true
  """
  def should_skip_history?(%__MODULE__{type: type} = dataset) do
    type in ["bike-scooter-sharing", "car-motorbike-sharing", "road-data"] or has_custom_tag?(dataset, "skip_history")
  end

  def has_licence_ouverte?(%__MODULE__{licence: licence}), do: licence in @licences_ouvertes

  @doc """
  iex> climate_resilience_bill?(%DB.Dataset{custom_tags: ["licence-osm"]})
  false
  iex> climate_resilience_bill?(%DB.Dataset{custom_tags: ["loi-climat-resilience", "foo"]})
  true
  """
  def climate_resilience_bill?(%__MODULE__{} = dataset), do: has_custom_tag?(dataset, "loi-climat-resilience")

  @doc """
  iex> has_custom_tag?(%DB.Dataset{custom_tags: ["foo"]}, "foo")
  true
  iex> has_custom_tag?(%DB.Dataset{custom_tags: ["foo"]}, "bar")
  false
  iex> has_custom_tag?(%DB.Dataset{custom_tags: nil}, "bar")
  false
  """
  def has_custom_tag?(%__MODULE__{custom_tags: custom_tags}, tag_name), do: tag_name in (custom_tags || [])

  @doc """
  iex> logo(%DB.Dataset{logo: "https://example.com/logo.png", custom_logo: nil})
  "https://example.com/logo.png"
  iex> logo(%DB.Dataset{logo: "https://example.com/logo.png", custom_logo: "https://example.com/custom.png"})
  "https://example.com/custom.png"
  """
  @spec logo(__MODULE__.t()) :: binary()
  def logo(%__MODULE__{logo: logo, custom_logo: custom_logo}), do: custom_logo || logo

  @doc """
  iex> full_logo(%DB.Dataset{full_logo: "https://example.com/logo.png", custom_full_logo: nil})
  "https://example.com/logo.png"
  iex> full_logo(%DB.Dataset{full_logo: "https://example.com/logo.png", custom_full_logo: "https://example.com/custom.png"})
  "https://example.com/custom.png"
  """
  @spec full_logo(__MODULE__.t()) :: binary()
  def full_logo(%__MODULE__{full_logo: full_logo, custom_full_logo: custom_full_logo}),
    do: custom_full_logo || full_logo
end
