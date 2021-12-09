defmodule DB.Dataset do
  @moduledoc """
  Dataset schema

  There's a trigger on update on postgres to update the search vector.
  There are also trigger on update on aom and region that will force an update on this model
  so the search vector is up-to-date.
  """
  alias Datagouvfr.Client.User
  alias DB.{AOM, Commune, DatasetGeographicView, LogsImport, Region, Repo, Resource}
  alias Phoenix.HTML.Link
  import Ecto.{Changeset, Query}
  import DB.Gettext
  require Logger
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "dataset" do
    field(:datagouv_id, :string)
    field(:spatial, :string)
    field(:created_at, :string)
    field(:description, :string)
    field(:frequency, :string)
    field(:last_update, :string)
    field(:licence, :string)
    field(:logo, :string)
    field(:full_logo, :string)
    field(:slug, :string)
    field(:tags, {:array, :string})
    field(:title, :string)
    field(:type, :string)
    field(:organization, :string)
    field(:has_realtime, :boolean)
    field(:is_active, :boolean)
    field(:population, :integer)
    field(:nb_reuses, :integer)
    field(:latest_data_gouv_comment_timestamp, :naive_datetime_usec)

    # When the dataset is linked to some cities
    # we ask in the backoffice for a name to display
    # (used in the long title of a dataset and to find the associated datasets)
    field(:associated_territory_name, :string)

    # A Dataset can be linked to *either*:
    # - a Region (and there is a special Region 'national' that represents the national datasets);
    # - an AOM;
    # - or a list of cities.
    belongs_to(:region, Region)
    belongs_to(:aom, AOM)
    many_to_many(:communes, Commune, join_through: "dataset_communes", on_replace: :delete)

    has_many(:resources, Resource, on_replace: :delete, on_delete: :delete_all)
    has_many(:logs_import, LogsImport, on_replace: :delete, on_delete: :delete_all)
    # A dataset can be "parent dataset" of many AOMs
    has_many(:child_aom, AOM, foreign_key: :parent_dataset_id)
  end

  @spec type_to_str_map() :: %{binary() => binary()}
  def type_to_str_map,
    do: %{
      "public-transit" => dgettext("dataset", "Public transit timetable"),
      "carpooling-areas" => dgettext("dataset", "Carpooling areas"),
      "stops-ref" => dgettext("dataset", "Stops referential"),
      "charging-stations" => dgettext("dataset", "Charging stations"),
      "air-transport" => dgettext("dataset", "Aerial"),
      "bike-scooter-sharing" => dgettext("dataset", "Bike and scooter sharing"),
      "car-motorbike-sharing" => dgettext("dataset", "Car and motorbike sharing"),
      "road-network" => dgettext("dataset", "Road networks"),
      "addresses" => dgettext("dataset", "Addresses"),
      "informations" => dgettext("dataset", "Other informations"),
      "private-parking" => dgettext("dataset", "Private parking"),
      "bike-way" => dgettext("dataset", "Bike way"),
      "bike-parking" => dgettext("dataset", "Bike parking"),
      "low-emission-zones" => dgettext("dataset", "Low emission zones")
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
        metadata: r.metadata,
        id: r.id,
        datagouv_id: r.datagouv_id,
        last_update: r.last_update,
        latest_url: r.latest_url,
        content_hash: r.content_hash,
        is_community_resource: r.is_community_resource,
        is_available: r.is_available,
        description: r.description,
        community_resource_publisher: r.community_resource_publisher,
        original_resource_url: r.original_resource_url,
        features: r.features,
        modes: r.modes,
        schema_name: r.schema_name,
        schema_version: r.schema_version
      }
    )
  end

  @spec preload_without_validations() :: Ecto.Query.t()
  defp preload_without_validations do
    s = no_validations_query()
    preload(__MODULE__, resources: ^s)
  end

  @spec filter_by_fulltext(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_fulltext(query, %{"q" => ""}), do: query

  defp filter_by_fulltext(query, %{"q" => q}) do
    where(
      query,
      [d],
      fragment("search_vector @@ plainto_tsquery('custom_french', ?) or unaccent(title) = unaccent(?)", ^q, ^q)
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

  @spec filter_by_feature(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_feature(query, %{"features" => feature}) do
    # Note: @> is the 'contains' operator
    query
    |> where(
      [d],
      fragment("(? IN (SELECT DISTINCT(dataset_id) FROM resource r where r.features @> ?::varchar[]))", d.id, ^feature)
    )
  end

  defp filter_by_feature(query, _), do: query

  @spec filter_by_mode(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_mode(query, %{"modes" => mode}) do
    query
    |> where(
      [d],
      fragment("(? IN (SELECT DISTINCT(dataset_id) FROM resource r where r.modes @> ?::varchar[]))", d.id, ^mode)
    )
  end

  defp filter_by_mode(query, _), do: query

  @spec filter_by_type(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_type(query, %{"type" => type}), do: where(query, [d], d.type == ^type)
  defp filter_by_type(query, _), do: query

  @spec filter_by_aom(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_aom(query, %{"aom" => aom_id}) do
    case parent_dataset(aom_id) do
      nil -> where(query, [d], d.aom_id == ^aom_id)
      parent_dataset_id -> where(query, [d], d.aom_id == ^aom_id or d.id == ^parent_dataset_id)
    end
  end

  defp filter_by_aom(query, _), do: query

  @spec parent_dataset(binary()) :: binary() | nil
  defp parent_dataset(aom_id) do
    aom =
      AOM
      |> where([a], a.id == ^aom_id)
      |> Repo.one()

    aom.parent_dataset_id
  end

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

  @spec filter_by_active(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_active(query, %{"list_inactive" => true}), do: query
  defp filter_by_active(query, _), do: where(query, [d], d.is_active)

  @spec list_datasets(map()) :: Ecto.Query.t()
  def list_datasets(%{} = params) do
    preload_without_validations()
    |> filter_by_active(params)
    |> filter_by_region(params)
    |> filter_by_feature(params)
    |> filter_by_mode(params)
    |> filter_by_category(params)
    |> filter_by_type(params)
    |> filter_by_aom(params)
    |> filter_by_commune(params)
    |> filter_by_fulltext(params)
    |> order_datasets(params)
  end

  @spec order_datasets(Ecto.Query.t(), map()) :: Ecto.Query.t()
  def order_datasets(datasets, %{"order_by" => "alpha"}), do: order_by(datasets, asc: :spatial)
  def order_datasets(datasets, %{"order_by" => "most_recent"}), do: order_by(datasets, desc: :created_at)

  def order_datasets(datasets, %{"q" => q}),
    do:
      order_by(datasets,
        desc: fragment("ts_rank_cd(search_vector, plainto_tsquery('custom_french', ?), 32) DESC, population", ^q)
      )

  def order_datasets(datasets, _params), do: datasets

  @spec changeset(map()) :: {:error, binary()} | {:ok, Ecto.Changeset.t()}
  def changeset(%{"datagouv_id" => datagouv_id} = params) when is_binary(datagouv_id) do
    dataset =
      case Repo.get_by(__MODULE__, datagouv_id: datagouv_id) do
        nil -> %__MODULE__{}
        dataset -> dataset
      end

    territory_name = Map.get(params, "associated_territory_name") || dataset.associated_territory_name

    dataset
    |> Repo.preload([:resources, :communes, :region])
    |> cast(params, [
      :datagouv_id,
      :spatial,
      :created_at,
      :description,
      :frequency,
      :organization,
      :last_update,
      :licence,
      :logo,
      :full_logo,
      :slug,
      :tags,
      :title,
      :type,
      :region_id,
      :nb_reuses,
      :is_active,
      :associated_territory_name,
      :latest_data_gouv_comment_timestamp
    ])
    |> cast_aom(params)
    |> cast_datagouv_zone(params, territory_name)
    |> cast_nation_dataset(params)
    |> cast_assoc(:resources)
    |> validate_required([:slug])
    |> cast_assoc(:region)
    |> cast_assoc(:aom)
    |> validate_territory_mutual_exclusion()
    |> has_real_time()
    |> case do
      %{valid?: false, changes: changes} = changeset when changes == %{} ->
        {:ok, %{changeset | action: :ignore}}

      %{valid?: true} = changeset ->
        {:ok, changeset}

      %{valid?: false} = errors ->
        Logger.warn("error while importing dataset: #{format_error(errors)}")
        {:error, format_error(errors)}
    end
  end

  def changeset(_) do
    {:error, "datagouv_id is a required field"}
  end

  @spec format_error(any()) :: binary()
  defp format_error(changeset), do: "#{inspect(Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end))}"

  @spec valid_gtfs(DB.Dataset.t()) :: [Resource.t()]
  def valid_gtfs(%__MODULE__{resources: nil}), do: []

  def valid_gtfs(%__MODULE__{resources: r, type: "public-transit"}),
    do: Enum.filter(r, &Resource.valid_and_available?/1)

  def valid_gtfs(%__MODULE__{resources: r}), do: r

  @spec link_to_datagouv(DB.Dataset.t()) :: any()
  def link_to_datagouv(%__MODULE__{} = dataset) do
    Link.link(
      dgettext("dataset", "See on data.gouv.fr"),
      to: datagouv_url(dataset),
      role: "link"
    )
  end

  @spec datagouv_url(DB.Dataset.t()) :: binary()
  def datagouv_url(%__MODULE__{slug: slug}) do
    Path.join([Application.fetch_env!(:transport, :datagouvfr_site), "datasets", slug])
  end

  @spec count_by_mode(binary()) :: number()
  def count_by_mode(tag) do
    __MODULE__
    |> join(:inner, [d], r in Resource, on: r.dataset_id == d.id)
    |> where([d, r], d.is_active and ^tag in r.modes)
    |> distinct([d], d.id)
    |> Repo.aggregate(:count, :id)
  end

  @spec count_coach() :: number()
  def count_coach do
    __MODULE__
    |> join(:inner, [d], r in Resource, on: r.dataset_id == d.id)
    |> join(:inner, [d], d_geo in DatasetGeographicView, on: d.id == d_geo.dataset_id)
    |> distinct([d], d.id)
    |> where([d, r, d_geo], d.is_active and "bus" in r.modes and d_geo.region_id == 14)
    # 14 is the national "region". It means that it is not bound to a region or local territory
    |> Repo.aggregate(:count, :id)
  end

  @spec count_by_type(binary()) :: any()
  def count_by_type(type) do
    __MODULE__
    |> where([d], d.type == ^type and d.is_active)
    |> Repo.aggregate(:count, :id)
  end

  @spec count_by_type :: map
  def count_by_type, do: for(type <- __MODULE__.types(), into: %{}, do: {type, count_by_type(type)})

  @spec count_public_transport_has_realtime :: number()
  def count_public_transport_has_realtime do
    __MODULE__
    |> where([d], d.has_realtime and d.is_active and d.type == "public-transit")
    |> Repo.aggregate(:count, :id)
  end

  @spec get_by_slug(binary) :: {:ok, __MODULE__.t()} | {:error, binary()}
  def get_by_slug(slug) do
    preload_without_validations()
    |> where(slug: ^slug)
    |> preload([:region, :aom, :communes])
    |> Repo.one()
    |> case do
      nil -> {:error, "Dataset with slug #{slug} not found"}
      dataset -> {:ok, dataset}
    end
  end

  @spec get_other_datasets(__MODULE__.t()) :: [__MODULE__.t()]
  def get_other_datasets(%__MODULE__{id: id, aom_id: aom_id}) when not is_nil(aom_id) do
    __MODULE__
    |> where([d], d.id != ^id)
    |> where([d], d.aom_id == ^aom_id)
    |> Repo.all()
  end

  def get_other_datasets(%__MODULE__{id: id, region_id: region_id}) when not is_nil(region_id) do
    __MODULE__
    |> where([d], d.id != ^id)
    |> where([d], d.region_id == ^region_id)
    |> Repo.all()
  end

  # for the datasets linked to multiple cities we use the
  # backoffice filled field 'associated_territory_name'
  # to get the other_datasets
  # This way we can control which datasets to link to
  def get_other_datasets(%__MODULE__{id: id, associated_territory_name: associated_territory_name}) do
    __MODULE__
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
    do: resources |> Stream.reject(fn r -> r.is_community_resource end) |> Enum.to_list()

  def official_resources(%__MODULE__{}), do: []

  @spec community_resources(__MODULE__.t()) :: list(Resource.t())
  def community_resources(%__MODULE__{resources: resources}),
    do: resources |> Stream.filter(fn r -> r.is_community_resource end) |> Enum.to_list()

  def community_resources(%__MODULE__{}), do: []

  @spec formats(__MODULE__.t()) :: [binary]
  def formats(%__MODULE__{resources: resources}) when is_list(resources) do
    resources
    |> Enum.map(fn r -> r.format end)
    |> Enum.sort()
    |> Enum.dedup()
  end

  def formats(_), do: []

  @spec validate(binary | integer | __MODULE__.t()) :: {:error, String.t()} | {:ok, nil}
  def validate(%__MODULE__{id: id, type: "public-transit"}), do: validate(id)
  def validate(%__MODULE__{}), do: {:ok, nil}
  def validate(id) when is_binary(id), do: id |> String.to_integer() |> validate()

  def validate(id) when is_integer(id) do
    Resource
    |> preload(:validation)
    |> where([r], r.dataset_id == ^id)
    |> Repo.all()
    |> Enum.map(fn r -> Resource.validate_and_save(r, true) end)
    |> Enum.any?(fn r -> match?({:error, _}, r) end)
    |> if do
      {:error, "Unable to validate dataset #{id}"}
    else
      {:ok, nil}
    end
  end

  @doc """
    Queries the Data Gouv API to determine the user datasets, then use each dataset id
    to achieve a look-up on our internal database, and return all local `DB.Dataset` objects.

    Any dataset available remotely (in Data Gouv) but not already synchronised locally
    will be missing in the returned result.
  """
  @spec user_datasets(Plug.Conn.t()) :: {:error, OAuth2.Error.t()} | {:ok, [__MODULE__.t()]}
  def user_datasets(%Plug.Conn{} = conn) do
    case User.datasets(conn) do
      {:ok, datasets} ->
        datagouv_ids = Enum.map(datasets, fn d -> d["id"] end)

        # this code has a caveat: if a remote (data gouv) dataset has not yet been synchronised/imported
        # to the local database for some reason, it won't appear in the result, despite existing remotely.
        {:ok,
         __MODULE__
         |> where([d], d.datagouv_id in ^datagouv_ids)
         |> order_by([d], desc: d.id)
         |> Repo.all()}

      error ->
        error
    end
  end

  @doc """
    Same as `user_datasets/1` but for organization datasets.
  """
  @spec user_org_datasets(Plug.Conn.t()) ::
          {:error, OAuth2.Error.t()} | {:ok, [__MODULE__.t()]}
  def user_org_datasets(%Plug.Conn{} = conn) do
    case User.org_datasets(conn) do
      {:ok, datasets} ->
        datagouv_ids = Enum.map(datasets, fn d -> d["id"] end)

        {:ok,
         __MODULE__
         |> where([d], d.datagouv_id in ^datagouv_ids)
         |> order_by([d], desc: d.id)
         |> Repo.all()}

      error ->
        error
    end
  end

  @spec get_expire_at(Date.t() | binary()) :: binary()
  def get_expire_at(%Date{} = date), do: get_expire_at("#{date}")

  def get_expire_at(date) do
    __MODULE__
    |> join(:inner, [d], r in Resource, on: r.dataset_id == d.id)
    |> group_by([d, r], d.id)
    |> having([d, r], fragment("max(?->>'end_date') = ?", r.metadata, ^date))
    |> preload([:resources])
    |> Repo.all()
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
          dgettext("dataset", "You need to fill either aom, region or use datagouv's zone")
        )
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
        add_error(changeset, :aom_id, dgettext("dataset", "Unable to find INSEE code '%{insee}'", insee: insee))

      commune ->
        case commune.aom_res do
          nil ->
            add_error(
              changeset,
              :aom_id,
              dgettext("dataset", "INSEE code '%{insee}' not associated with an AOM", insee: insee)
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

      change(changeset, region: national, region_id: national.id)
    else
      add_error(changeset, :region, dgettext("dataset", "A dataset cannot be national and regional"))
    end
  end

  defp cast_nation_dataset(changeset, _), do: changeset

  @spec get_commune_by_insee(binary()) :: Commune.t() | nil
  defp get_commune_by_insee(insee) do
    Commune
    |> Repo.get_by(insee: insee)
    |> case do
      nil ->
        Logger.warn("Unable to find zone with INSEE #{insee}")
        nil

      commune ->
        commune
    end
  end

  @spec cast_datagouv_zone(Ecto.Changeset.t(), map(), binary()) :: Ecto.Changeset.t()
  defp cast_datagouv_zone(changeset, _, nil) do
    changeset
    |> change
    |> put_assoc(:communes, [])
  end

  defp cast_datagouv_zone(changeset, _, "") do
    changeset
    |> change
    |> put_assoc(:communes, [])
  end

  defp cast_datagouv_zone(changeset, %{"zones" => zones_insee}, _associated_territory_name) do
    communes =
      zones_insee
      |> Enum.map(&get_commune_by_insee/1)
      |> Enum.filter(fn z -> not is_nil(z) end)

    changeset
    |> change
    |> put_assoc(:communes, communes)
  end

  defp has_real_time(changeset) do
    has_realtime = changeset |> get_field(:resources) |> Enum.any?(&Resource.is_real_time?/1)
    changeset |> change(has_realtime: has_realtime)
  end
end
