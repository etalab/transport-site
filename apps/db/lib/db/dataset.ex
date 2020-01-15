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

  schema "dataset" do
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

    belongs_to(:region, Region)
    belongs_to(:aom, AOM)

    has_many(:resources, Resource, on_replace: :delete, on_delete: :delete_all)
  end

  def type_to_str,
    do: %{
      "public-transit" => dgettext("dataset", "Public transit timetable"),
      "carsharing-areas" => dgettext("dataset", "Carsharing areas"),
      "stops-ref" => dgettext("dataset", "Stops referential"),
      "charging-stations" => dgettext("dataset", "Charging stations"),
      "micro-mobility" => dgettext("dataset", "Micro mobility"),
      "air-transport" => dgettext("dataset", "Aerial"),
      "train" => dgettext("dataset", "Train timetable"),
      "bike-sharing" => dgettext("dataset", "Bike sharing"),
      "road-network" => dgettext("dataset", "Road networks"),
      "long-distance-coach" => dgettext("dataset", "Long distance coach")
    }

  def type_to_str(type), do: type_to_str()[type]

  def types, do: Map.keys(type_to_str())

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

  def preload_without_validations(q) do
    s = no_validations_query()
    preload(q, resources: ^s)
  end

  def select_active(q), do: where(q, [d], d.is_active)

  def search_datasets(q, s \\ []) do
    resource_query = no_validations_query()

    __MODULE__
    |> where(
      [d],
      fragment("search_vector @@ plainto_tsquery('custom_french', ?) or unaccent(title) = unaccent(?)", ^q, ^q)
    )
    |> order_by([l],
      desc: fragment("ts_rank_cd(search_vector, plainto_tsquery('custom_french', ?), 32) DESC, population", ^q)
    )
    |> select_active
    |> select_or_not(s)
    |> preload(resources: ^resource_query)
  end

  def list_datasets, do: __MODULE__ |> select_active |> preload_without_validations
  def list_datasets([]), do: list_datasets()

  def list_datasets(s) when is_list(s) do
    from(d in __MODULE__,
      select: ^s,
      preload: [:resources, :region, :aom]
    )
  end

  def list_datasets(filters, s \\ [])
  def list_datasets(%{"q" => ""} = params, s), do: s |> list_datasets() |> order_datasets(params)
  def list_datasets(%{"q" => q} = params, s), do: q |> search_datasets(s) |> order_datasets(params)

  defp filter_by_region(query, %{"region" => region_id} = params) do
    query
    |> join(:right, [d], d_geo in DatasetGeographicView, on: d.id == d_geo.dataset_id)
    |> where([d, d_geo], d_geo.region_id == ^region_id)
  end

  defp filter_by_region(query, _), do: query

  defp filter_by_category(query, %{"filter" => filter_key}) do
    case filter_key do
      "has_realtime" -> where(query, [d], d.has_realtime == true)
      "intercities_public_transport" -> where(query, [d], not is_nil(d.region_id) and d.type == "public-transit")
      "urban_public_transport" -> where(query, [d], not is_nil(d.aom_id) and d.type == "public-transit")
      _ -> query
    end
  end

  defp filter_by_category(query, _), do: query

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

  defp filter_by_type(query, %{"type" => type}), do: where(query, [d], d.type == ^type)
  defp filter_by_type(query, _), do: query

  defp filter_by_aom(query, %{"aom" => aom_id}), do: where(query, [d], d.aom_id == ^aom_id)
  defp filter_by_aom(query, _), do: query

  def list_datasets(%{} = params, query) do
    query
    |> list_datasets()
    |> filter_by_tags(params)
    |> filter_by_category(params)
    |> filter_by_type(params)
    |> filter_by_region(params)
    |> filter_by_aom(params)
    |> order_datasets(params)
  end

  def order_datasets(datasets, %{"order_by" => "alpha"}), do: order_by(datasets, asc: :title)
  def order_datasets(datasets, %{"order_by" => "most_recent"}), do: order_by(datasets, desc: :created_at)
  def order_datasets(datasets, _params), do: datasets

  def changeset(_dataset, params) do
    dataset =
      case Repo.get_by(__MODULE__, datagouv_id: params["datagouv_id"]) do
        nil -> %__MODULE__{}
        dataset -> dataset
      end

    dataset
    |> Repo.preload(:resources)
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
      :is_active
    ])
    |> cast_aom(params)
    |> cast_assoc(:resources)
    |> validate_required([:slug])
    |> validate_mutual_exclusion([:region_id, :aom_id], dgettext("dataset", "You need to fill either aom or region"))
    |> cast_assoc(:region)
    |> cast_assoc(:aom)
    |> case do
      %{valid?: false, changes: changes} = changeset when changes == %{} ->
        {:ok, %{changeset | action: :ignore}}

      %{valid?: true} = changeset ->
        {:ok, changeset}

      %{valid?: false, errors: errors} ->
        {:error, format_error(errors)}

      _ ->
        {:error, "unknown"}
    end
  end

  defp format_error([]), do: ""
  defp format_error([{_key, {msg, _extra}}]), do: "#{msg}"
  defp format_error([{_key, {msg, _extra}} | errors]), do: "#{msg}, #{format_error(errors)}"

  def valid_gtfs(%__MODULE__{resources: nil}), do: []
  def valid_gtfs(%__MODULE__{resources: r, type: "public-transit"}), do: Enum.filter(r, &Resource.valid?/1)
  def valid_gtfs(%__MODULE__{resources: r}), do: r

  @doc """
  Builds a licence.
  ## Examples
      iex> %Dataset{licence: "fr-lo"}
      ...> |> Dataset.localise_licence
      "Open Licence"
      iex> %Dataset{licence: "Libertarian"}
      ...> |> Dataset.localise_licence
      "Not specified"
  """
  @spec localise_licence(%__MODULE__{}) :: String.t()
  def localise_licence(%__MODULE__{licence: licence}) do
    case licence do
      "fr-lo" -> dgettext("dataset", "fr-lo")
      "odc-odbl" -> dgettext("dataset", "odc-odbl")
      "other-open" -> dgettext("dataset", "other-open")
      _ -> dgettext("dataset", "notspecified")
    end
  end

  def link_to_datagouv(%__MODULE__{} = dataset) do
    Link.link(
      dgettext("dataset", "See on data.gouv.fr"),
      to: datagouv_url(dataset),
      role: "link"
    )
  end

  def datagouv_url(%__MODULE__{slug: slug}) do
    Path.join([System.get_env("DATAGOUVFR_SITE"), "datasets", slug])
  end

  def count_by_resource_tag(tag) do
    __MODULE__
    |> join(:inner, [d], r in Resource, on: r.dataset_id == d.id)
    |> where([_d, r], ^tag in r.auto_tags)
    |> Repo.aggregate(:count, :id)
  end

  def count_by_type("train"), do: count_by_resource_tag("rail")

  def count_by_type(type) do
    query = from(d in __MODULE__, where: d.type == ^type)

    Repo.aggregate(query, :count, :id)
  end

  def count_by_type, do: for(type <- __MODULE__.types(), into: %{}, do: {type, count_by_type(type)})

  def filter_has_realtime, do: from(d in __MODULE__, where: d.has_realtime == true)
  def count_has_realtime, do: Repo.aggregate(filter_has_realtime(), :count, :id)

  @spec get_by(keyword) :: Dataset.t()
  def get_by(options) do
    slug = Keyword.get(options, :slug)

    query =
      __MODULE__
      |> where(slug: ^slug)
      |> preload_without_validations()

    query =
      if Keyword.get(options, :preload, false) do
        query |> preload([:region, :aom])
      else
        query
      end

    query
    |> Repo.one()
  end

  @spec get_other_datasets(DB.Dataset.t()) :: [DB.Dataset.t()]
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

  def get_other_dataset(_), do: []

  def get_organization(%__MODULE__{aom_id: aom_id}) when not is_nil(aom_id) do
    Repo.get(AOM, aom_id)
  end

  def get_organization(%__MODULE__{region_id: region_id}) when not is_nil(region_id) do
    Repo.get(Region, region_id)
  end

  def get_organization(_), do: nil

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

  def get_covered_area_names(_), do: "National"

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

  @spec formats(DB.Dataset.t()) :: [binary]
  def formats(%__MODULE__{resources: resources}) when is_list(resources) do
    resources
    |> Enum.map(fn r -> r.format end)
    |> Enum.sort()
    |> Enum.dedup()
  end

  def formats(_), do: []

  @spec validate(binary | integer | DB.Dataset.t()) :: {:error, String.t()} | {:ok, nil}
  def validate(%__MODULE__{id: id, type: type}) do
    if Resource.is_transit_file?(type), do: validate(id), else: {:ok, nil}
  end

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
      {:ok, nil}
    end
  end

  @spec user_datasets(Plug.Conn.t()) :: {:error, OAuth2.Error.t()} | {:ok, [Transport.Dataset.t()]}
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
          {:error, OAuth2.Error.t()} | {:ok, [DB.Dataset.t()]}
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

  def history_bucket_id(%__MODULE__{} = dataset) do
    "#{System.get_env("CELLAR_NAMESPACE")}dataset-#{dataset.datagouv_id}"
  end

  def get_expire_at(%Date{} = date), do: get_expire_at("#{date}")

  def get_expire_at(date) do
    __MODULE__
    |> join(:inner, [d], r in Resource, on: r.dataset_id == d.id)
    |> group_by([d, r], d.id)
    |> having([d, r], fragment("max(?->>'end_date') = ?", r.metadata, ^date))
    |> preload([:resources])
    |> Repo.all()
  end

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

  defp history_resource_path(bucket, name), do: Path.join(["http://", bucket <> @cellar_host, name])

  defp validate_mutual_exclusion(changeset, fields, error) do
    fields
    |> Enum.count(&(get_field(changeset, &1) not in ["", nil]))
    |> case do
      1 ->
        changeset

      _ ->
        Enum.reduce(
          fields,
          changeset,
          fn field, changeset -> add_error(changeset, field, error) end
        )
    end
  end

  defp select_or_not(res, []), do: res
  defp select_or_not(res, s), do: select(res, ^s)

  defp cast_aom(changeset, %{"insee" => ""}), do: changeset
  defp cast_aom(changeset, %{"insee" => nil}), do: changeset

  defp cast_aom(changeset, %{"insee" => insee}) do
    Commune
    |> preload([:aom_res])
    |> Repo.get_by(insee: insee)
    |> case do
      nil -> add_error(changeset, :aom_id, dgettext("dataset", "Unable to find INSEE code"))
      commune -> change(changeset, aom_id: commune.aom_res.id)
    end
  end

  defp cast_aom(changeset, _), do: changeset
end
