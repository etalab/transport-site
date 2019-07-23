defmodule Transport.Dataset do
  @moduledoc """
  Dataset schema

  There's a trigger on update on postgres to update the search vector.
  There are also trigger on update on aom and region that will force an update on this model
  so the search vector is up-to-date.
  """
  alias Phoenix.HTML.Link
  alias Transport.{AOM, Region, Repo, Resource}
  import Ecto.{Changeset, Query}
  import TransportWeb.Gettext
  require Logger
  use Ecto.Schema

  schema "dataset" do
    field :datagouv_id, :string
    field :spatial, :string
    field :created_at, :string
    field :description, :string
    field :frequency, :string
    field :last_update, :string
    field :licence, :string
    field :logo, :string
    field :full_logo, :string
    field :slug, :string
    field :tags, {:array, :string}
    field :title, :string
    field :type, :string
    field :organization, :string
    field :has_realtime, :boolean
    field :is_active, :boolean
    field :population, :integer

    belongs_to :region, Region
    belongs_to :aom, AOM

    has_many :resources, Resource, on_replace: :delete, on_delete: :delete_all
  end

  def type_to_str, do: %{
    "public-transit" => dgettext("dataset", "Public transit"),
    "carsharing-areas" => dgettext("dataset", "Carsharing areas"),
    "stops-ref" => dgettext("dataset", "Stops referential"),
    "charging-stations" => dgettext("dataset", "Charging stations"),
    "micro-mobility" => dgettext("dataset", "Micro mobility"),
    "air-transport" => dgettext("dataset", "Aerial"),
    "train" => dgettext("dataset", "Train"),
    "bike-sharing" => dgettext("dataset", "Bike sharing"),
    "long-distance-coach" => dgettext("dataset", "Long distance coach")
  }

  def type_to_str(type), do: type_to_str()[type]

  def types, do: Map.keys(type_to_str())

  defp no_validations_query do
    from r in Resource,
      select: %Resource{
        format: r.format,
        title: r.title,
        url: r.url,
        metadata: r.metadata,
        id: r.id,
        last_update: r.last_update,
        latest_url: r.latest_url
      },
      where: r.is_available
  end

  def preload_without_validations(q) do
    s = no_validations_query()
    preload(q, [resources: ^s])
  end

  def select_active(q), do: where(q, [d], d.is_active)

  def search_datasets(q, s \\ []) do
    resource_query = no_validations_query()

    __MODULE__
    |> where([d], fragment("search_vector @@ plainto_tsquery('simple', ?)", ^q))
    |> order_by([l], [desc: fragment("ts_rank_cd(search_vector, plainto_tsquery('simple', ?), 32) DESC, population", ^q)])
    |> select_active
    |> select_or_not(s)
    |> preload([resources: ^resource_query])
  end

  def list_datasets, do: __MODULE__ |> select_active |> preload_without_validations
  def list_datasets([]), do: list_datasets()
  def list_datasets(s) when is_list(s) do
    from d in __MODULE__,
     select: ^s,
     preload: [:resources, :region, :aom]
  end

  def list_datasets(filters, s \\ [])
  def list_datasets(%{"q" => ""} = params, s), do: s |> list_datasets() |> order_datasets(params)
  def list_datasets(%{"q" => q} = params, s), do: q |> search_datasets(s) |> order_datasets(params)
  def list_datasets(%{"region" => region_id} = params, s) do
    sub = AOM
    |> where([a], a.region_id == ^region_id)
    |> select([a], a.id)
    |> Repo.all()

    s
    |> list_datasets()
    |> where([d], d.aom_id in ^sub)
    |> or_where([r], r.region_id == ^region_id)
    |> order_datasets(params)
  end
  def list_datasets(%{"filter" => "has_realtime"} = params, s) do
    s
    |> list_datasets()
    |> where([d], d.has_realtime == true)
    |> order_datasets(params)
  end
  def list_datasets(%{} = params, s) do
    filters =
      params
      |> Map.take(["commune", "type"])
      |> Map.to_list
      |> Enum.map(fn
        {"commune", v} -> {:aom_id, v}
        {"type", type} -> {:type, type}
      end)
      |> Keyword.new

    s
    |> list_datasets()
    |> where([d], ^filters)
    |> order_datasets(params)
  end

  def order_datasets(datasets, %{"order_by" => "alpha"}), do: order_by(datasets, asc: :title)
  def order_datasets(datasets, %{"order_by" => "most_recent"}), do: order_by(datasets, desc: :created_at)
  def order_datasets(datasets, _params), do: datasets

  def changeset(_dataset, params) do
    dataset = case Repo.get_by(__MODULE__, datagouv_id: params["datagouv_id"]) do
      nil -> %__MODULE__{}
      dataset -> dataset
    end

    dataset
    |> Repo.preload(:resources)
    |> cast(params, [:datagouv_id, :spatial, :created_at, :description, :frequency, :organization,
    :last_update, :licence, :logo, :full_logo, :slug, :tags, :title, :type, :region_id,
     :has_realtime, :is_active])
    |> cast_aom(params)
    |> cast_assoc(:resources)
    |> validate_required([:slug])
    |> validate_mutual_exclusion([:region_id, :aom_id], dgettext("dataset", "You need to fill either aom or region"))
    |> cast_assoc(:region)
    |> cast_assoc(:aom)
    |> case do
      %{valid?: false, changes: changes} = changeset when changes == %{} ->
        %{changeset | action: :ignore}
      changeset ->
        changeset
    end
  end

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
  @spec localise_licence(%__MODULE__{}) :: String.t
  def localise_licence(%__MODULE__{licence: licence}) do
    case licence do
      "fr-lo" -> dgettext("reusable_data", "fr-lo")
      "odc-odbl" -> dgettext("reusable_data", "odc-odbl")
      "other-open" -> dgettext("reusable_data", "other-open")
      _ -> dgettext("reusable_data", "notspecified")
    end
  end

  def link_to_datagouv(%__MODULE__{} = dataset) do
    Link.link(
      dgettext("page-shortlist", "See on data.gouv.fr"),
      to: datagouv_url(dataset),
      role: "link"
    )
  end

  def datagouv_url(%__MODULE__{slug: slug}) do
    Path.join([System.get_env("DATAGOUVFR_SITE"), "datasets", slug])
  end

  def count_by_type(type) do
    query = from d in __MODULE__, where: d.type == ^type

    Repo.aggregate(query, :count, :id)
  end

  def count_by_type, do: for type <- __MODULE__.types(), into: %{}, do: {type, count_by_type(type)}

  def filter_has_realtime, do: from d in __MODULE__, where: d.has_realtime == true
  def count_has_realtime, do: Repo.aggregate(filter_has_realtime(), :count, :id)

  @spec get_by(keyword) :: Dataset.t()
  def get_by(options) do
    slug = Keyword.get(options, :slug)

    query =
      __MODULE__
      |> where(slug: ^slug)
      |> preload_without_validations()

    if Keyword.get(options, :preload, false) do
      query |> preload([:region, :aom])
    else
      query
    end
    |> Repo.one()
  end

  @spec get_other_datasets(Transport.Dataset.t()) :: [Transport.Dataset.t()]
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
        Enum.reject(names, & &1 == nil)
      {:ok, %{rows: []}} -> ""
      {:error, error} ->
        Logger.error error
        ""
    end
  end

  @spec nom(Transport.Dataset.t()) :: binary
  def nom(%__MODULE__{aom: %{nom: nom}}), do: String.capitalize(nom)
  def nom(%__MODULE__{region: %{nom: nom}}), do: String.capitalize(nom)
  def nom(_), do: ""

  @spec formats(Transport.Dataset.t()) :: [binary]
  def formats(%__MODULE__{resources: resources}) when is_list(resources) do
    resources
    |> Enum.map(fn r -> r.format end )
    |> Enum.sort()
    |> Enum.dedup()
  end
  def formats(_), do: []

  ## Private functions

  defp validate_mutual_exclusion(changeset, fields, error) do
    fields
    |> Enum.count(& get_field(changeset, &1) not in ["", nil])
    |> case do
      1 -> changeset
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

  defp cast_aom(changeset, %{"insee_commune_principale" => ""}), do: changeset
  defp cast_aom(changeset, %{"insee_commune_principale" => nil}), do: changeset
  defp cast_aom(changeset, %{"insee_commune_principale" => insee}) do
    case Repo.get_by(AOM, insee_commune_principale: insee) do
      nil -> add_error(changeset, :aom_id, dgettext("dataset", "Unable to find INSEE code"))
      aom -> change(changeset, [aom_id: aom.id])
    end
  end
  defp cast_aom(changeset, _), do: changeset
end
