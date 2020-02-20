defmodule DB.Dataset do
  @moduledoc """
  Dataset schema

  There's a trigger on update on postgres to update the search vector.
  There are also trigger on update on aom and region that will force an update on this model
  so the search vector is up-to-date.
  """
  alias Datagouvfr.Client.User
  alias DB.{AOM, Commune, DatasetGeographicView, Region, Repo, Resource}
  alias ExAws.S3
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
    many_to_many(:communes, Commune, join_through: "dataset_communes")

    has_many(:resources, Resource, on_replace: :delete, on_delete: :delete_all)
  end

  @spec type_to_str_map() :: %{binary() => binary()}
  def type_to_str_map,
    do: %{
      "public-transit" => dgettext("dataset", "Public transit timetable"),
      "carsharing-areas" => dgettext("dataset", "Carsharing areas"),
      "stops-ref" => dgettext("dataset", "Stops referential"),
      "charging-stations" => dgettext("dataset", "Charging stations"),
      "micro-mobility" => dgettext("dataset", "Micro mobility"),
      "air-transport" => dgettext("dataset", "Aerial"),
      "bike-sharing" => dgettext("dataset", "Bike sharing"),
      "road-network" => dgettext("dataset", "Road networks"),
      "addresses" => dgettext("dataset", "Addresses")
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
        last_update: r.last_update,
        latest_url: r.latest_url,
        content_hash: r.content_hash,
        auto_tags: r.auto_tags
      },
      where: r.is_available
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

  @spec filter_by_tags(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_tags(query, %{"tags" => tags}) do
    resources =
      Resource
      |> where([r], fragment("? @> ?::varchar[]", r.auto_tags, ^tags))
      |> distinct([r], r.dataset_id)
      |> select([r], %Resource{dataset_id: r.dataset_id})

    query
    |> join(:inner, [d], r in subquery(resources), on: d.id == r.dataset_id)
  end

  defp filter_by_tags(query, _), do: query

  @spec filter_by_type(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_type(query, %{"type" => type}), do: where(query, [d], d.type == ^type)
  defp filter_by_type(query, _), do: query

  @spec filter_by_aom(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_aom(query, %{"aom" => aom_id}), do: where(query, [d], d.aom_id == ^aom_id)
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

  @spec filter_by_active(Ecto.Query.t(), map()) :: Ecto.Query.t()
  defp filter_by_active(query, %{"list_inactive" => true}), do: query
  defp filter_by_active(query, _), do: where(query, [d], d.is_active)

  @spec list_datasets(map()) :: Ecto.Query.t()
  def list_datasets(%{} = params) do
    preload_without_validations()
    |> filter_by_active(params)
    |> filter_by_region(params)
    |> filter_by_tags(params)
    |> filter_by_category(params)
    |> filter_by_type(params)
    |> filter_by_aom(params)
    |> filter_by_commune(params)
    |> filter_by_fulltext(params)
    |> order_datasets(params)
  end

  @spec order_datasets(Ecto.Query.t(), map()) :: Ecto.Query.t()
  def order_datasets(datasets, %{"order_by" => "alpha"}), do: order_by(datasets, asc: :title)
  def order_datasets(datasets, %{"order_by" => "most_recent"}), do: order_by(datasets, desc: :created_at)

  def order_datasets(datasets, %{"q" => q}),
    do:
      order_by(datasets,
        desc: fragment("ts_rank_cd(search_vector, plainto_tsquery('custom_french', ?), 32) DESC, population", ^q)
      )

  def order_datasets(datasets, _params), do: datasets

  @spec changeset(map()) :: {:error, binary()} | {:ok, Ecto.Changeset.t()}
  def changeset(params) do
    dataset =
      case Repo.get_by(__MODULE__, datagouv_id: params["datagouv_id"]) do
        nil -> %__MODULE__{}
        dataset -> dataset
      end

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
      :has_realtime,
      :nb_reuses,
      :is_active,
      :associated_territory_name
    ])
    |> cast_aom(params)
    |> cast_datagouv_zone(params)
    |> cast_nation_dataset(params)
    |> cast_assoc(:resources)
    |> validate_required([:slug])
    |> cast_assoc(:region)
    |> cast_assoc(:aom)
    |> validate_territory_mutual_exclusion()
    |> validate_territory_name(params)
    |> case do
      %{valid?: false, changes: changes} = changeset when changes == %{} ->
        {:ok, %{changeset | action: :ignore}}

      %{valid?: true} = changeset ->
        {:ok, changeset}

      %{valid?: false, errors: errors} ->
        {:error, format_error(errors)}
    end
  end

  @spec format_error(keyword()) :: binary()
  defp format_error([]), do: ""
  defp format_error([{_key, {msg, _extra}}]), do: "#{msg}"
  defp format_error([{_key, {msg, _extra}} | errors]), do: "#{msg}, #{format_error(errors)}"

  @spec valid_gtfs(DB.Dataset.t()) :: [Resource.t()]
  def valid_gtfs(%__MODULE__{resources: nil}), do: []
  def valid_gtfs(%__MODULE__{resources: r, type: "public-transit"}), do: Enum.filter(r, &Resource.valid?/1)
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
    Path.join([System.get_env("DATAGOUVFR_SITE"), "datasets", slug])
  end

  @spec count_by_resource_tag(binary()) :: number()
  def count_by_resource_tag(tag) do
    __MODULE__
    |> join(:inner, [d], r in Resource, on: r.dataset_id == d.id)
    |> where([_d, r], ^tag in r.auto_tags)
    |> Repo.aggregate(:count, :id)
  end

  @spec count_coach() :: number()
  def count_coach do
    __MODULE__
    |> join(:right, [d], d_geo in DatasetGeographicView, on: d.id == d_geo.dataset_id)
    # 14 is the national "region". It means that it is not bound to a region or local territory
    |> where([d, d_geo], d.type == "public-transit" and d_geo.region_id == 14)
    |> Repo.aggregate(:count, :id)
  end

  @spec count_by_type(binary()) :: any()
  def count_by_type(type) do
    query = from(d in __MODULE__, where: d.type == ^type)

    Repo.aggregate(query, :count, :id)
  end

  def count_by_type, do: for(type <- __MODULE__.types(), into: %{}, do: {type, count_by_type(type)})
  def count_has_realtime, do: Repo.aggregate(filter_has_realtime(), :count, :id)

  @spec filter_has_realtime() :: Ecto.Query.t()
  defp filter_has_realtime, do: from(d in __MODULE__, where: d.has_realtime == true)

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
  def get_territory(%__MODULE__{aom_id: aom_id}) when not is_nil(aom_id) do
    case Repo.get(AOM, aom_id) do
      nil -> {:error, "Could not find territory of AOM with id #{aom_id}"}
      aom -> {:ok, aom.nom}
    end
  end

  def get_territory(%__MODULE__{region_id: region_id}) when not is_nil(region_id) do
    case Repo.get(Region, region_id) do
      nil -> {:error, "Could not find territory of Region with id #{region_id}"}
      region -> {:ok, region.nom}
    end
  end

  def get_territory(%__MODULE__{associated_territory_name: associated_territory_name}),
    do: {:ok, associated_territory_name}

  def get_territory(_), do: {:error, "Trying to find the territory of an unkown entity"}

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
    |> where([r], r.dataset_id == ^id)
    |> Repo.all()
    |> Enum.map(&Resource.validate_and_save/1)
    |> Enum.any?(fn r -> match?({:error, _}, r) end)
    |> if do
      {:error, "Unable to validate dataset #{id}"}
    else
      :ok
    end
  end

  @spec user_datasets(Plug.Conn.t()) :: {:error, OAuth2.Error.t()} | {:ok, [__MODULE__.t()]}
  def user_datasets(%Plug.Conn{} = conn) do
    case User.datasets(conn) do
      {:ok, datasets} ->
        datagouv_ids = Enum.map(datasets, fn d -> d["id"] end)

        {:ok,
         __MODULE__
         |> where([d], d.datagouv_id in ^datagouv_ids)
         |> Repo.all()}

      error ->
        error
    end
  end

  @spec user_org_datasets(Plug.Conn.t()) ::
          {:error, OAuth2.Error.t()} | {:ok, [__MODULE__.t()]}
  def user_org_datasets(%Plug.Conn{} = conn) do
    case User.org_datasets(conn) do
      {:ok, datasets} ->
        datagouv_ids = Enum.map(datasets, fn d -> d["id"] end)

        {:ok,
         __MODULE__
         |> where([d], d.datagouv_id in ^datagouv_ids)
         |> Repo.all()}

      error ->
        error
    end
  end

  @spec history_resources(DB.Dataset.t()) :: [map()]
  def history_resources(%__MODULE__{} = dataset) do
    if Application.get_env(:ex_aws, :access_key_id) == nil ||
         Application.get_env(:ex_aws, :secret_access_key) == nil do
      # if the cellar credential are missing, we skip the whole history
      []
    else
      try do
        bucket = history_bucket_id(dataset)

        bucket
        |> S3.list_objects()
        |> ExAws.stream!()
        |> Enum.to_list()
        |> Enum.map(fn f ->
          metadata = fetch_history_metadata(bucket, f.key)

          is_current =
            dataset.resources
            |> Enum.map(fn r -> r.content_hash end)
            |> Enum.any?(fn hash -> !is_nil(hash) && metadata["content-hash"] == hash end)

          %{
            name: f.key,
            href: history_resource_path(bucket, f.key),
            metadata: fetch_history_metadata(bucket, f.key),
            is_current: is_current,
            last_modified: f.last_modified
          }
        end)
        |> Enum.sort_by(fn f -> f.last_modified end, &Kernel.>=/2)
      rescue
        e in ExAws.Error ->
          Logger.error("error while accessing the S3 bucket: #{inspect(e)}")
          []
      end
    end
  end

  @spec history_bucket_id(__MODULE__.t()) :: binary()
  def history_bucket_id(%__MODULE__{} = dataset) do
    "#{System.get_env("CELLAR_NAMESPACE")}dataset-#{dataset.datagouv_id}"
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

  @spec fetch_history_metadata(binary(), binary()) :: map()
  def fetch_history_metadata(bucket, obj_key) do
    bucket
    |> S3.head_object(obj_key)
    |> ExAws.request!()
    |> Map.get(:headers)
    |> Map.new(fn {k, v} -> {String.replace(k, "x-amz-meta-", ""), v} end)
    |> Map.take(["format", "title", "start", "end", "updated-at", "content-hash"])
  end

  ## Private functions
  @cellar_host ".cellar-c2.services.clever-cloud.com/"

  @spec history_resource_path(binary(), binary()) :: binary()
  defp history_resource_path(bucket, name), do: Path.join(["http://", bucket <> @cellar_host, name])

  @spec validate_territory_name(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  defp validate_territory_name(changeset, %{
         "use_datagouv_zones" => "true",
         "associated_territory_name" => n
       })
       when n != "" do
    changeset
  end

  defp validate_territory_name(changeset, %{"use_datagouv_zones" => "true"}) do
    add_error(
      changeset,
      :region,
      dgettext("dataset", "If the data.gouv's zones are used, you should fill the associated territory name")
    )
  end

  defp validate_territory_name(changeset, _) do
    changeset
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
  defp cast_aom(changeset, %{"insee" => ""}), do: changeset
  defp cast_aom(changeset, %{"insee" => nil}), do: changeset

  defp cast_aom(changeset, %{"insee" => insee}) do
    Commune
    |> preload([:aom_res])
    |> Repo.get_by(insee: insee)
    |> case do
      nil -> add_error(changeset, :aom_id, dgettext("dataset", "Unable to find INSEE code '%{insee}'", insee: insee))
      commune -> change(changeset, aom_id: commune.aom_res.id)
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

  @spec cast_datagouv_zone(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  defp cast_datagouv_zone(changeset, %{"zones" => zones_insee, "use_datagouv_zones" => "true"}) do
    communes =
      zones_insee
      |> Enum.map(&get_commune_by_insee/1)
      |> Enum.filter(fn z -> not is_nil(z) end)

    changeset
    |> change
    |> put_assoc(:communes, communes)
  end

  defp cast_datagouv_zone(changeset, _), do: changeset
end
