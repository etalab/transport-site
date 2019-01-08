defmodule Transport.Dataset do
  @moduledoc """
  Dataset schema
  """
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

    belongs_to :region, Region
    belongs_to :aom, AOM

    has_many :resources, Resource, on_replace: :delete, on_delete: :delete_all
  end

  def search_datasets(search_string, s \\ []) do
    document_q = __MODULE__
    |> join(:left, [d], aom in AOM, on: d.aom_id == aom.id)
    |> join(:left, [d], region in Region, on: d.region_id == region.id)
    |> select([d, a, r], %{
      id: d.id,
      document: fragment(
        """
        setweight(to_tsvector('french', coalesce(?, '')), 'A') ||
        setweight(to_tsvector('french', coalesce(?, '')), 'A') ||
        setweight(to_tsvector('french', coalesce(?, '')), 'B') ||
        setweight(to_tsvector('french', coalesce(?, '')), 'B') ||
        setweight(to_tsvector('french', array_to_string(?, ',')), 'B') ||
        setweight(to_tsvector('french', coalesce(?, '')), 'D')
        """, a.insee_commune_principale, d.spatial, a.nom, r.nom, d.tags, d.description
      )
    })

    sub =
       document_q
    |> subquery()
    |> where([d], fragment("? @@ plainto_tsquery('french', ?)", d.document, ^search_string))
    |> order_by([d], fragment("ts_rank(?, plainto_tsquery('french', ?)) DESC", d.document, ^search_string))

    __MODULE__
    |> join(:inner, [d], doc in subquery(sub), on: doc.id == d.id)
    |> select_or_not(s)
    |> preload([:resources])
  end

  def list_datasets, do: from d in __MODULE__, preload: [:resources]
  def list_datasets([]), do: list_datasets()
  def list_datasets(s) when is_list(s), do: from d in __MODULE__, select: ^s, preload: [:resources]

  def list_datasets(filters, s \\ [])
  def list_datasets(%{"q" => q}, s), do: search_datasets(q, s)
  def list_datasets(%{} = params, s) do
    filters =
      params
      |> Map.take(["commune", "region", "type"])
      |> Map.to_list
      |> Enum.map(fn
        {"commune", v} -> {:aom_id, v}
        {"region", v} -> {:region_id, v}
        {"type", type} -> {:type, type}
      end)
      |> Keyword.new

    s
    |> list_datasets()
    |> where([d], ^filters)
  end

  def changeset(dataset, params) do
    dataset
    |> Repo.preload(:resources)
    |> cast(params, [:datagouv_id, :spatial, :created_at, :description, :frequency,
    :last_update, :licence, :logo, :full_logo, :slug, :tags, :title, :type, :region_id, :aom_id])
    |> cast_assoc(:resources)
    |> validate_required([:slug])
    |> validate_mutual_exclusion([:region_id, :aom_id], dgettext("dataset", "You need to fill either aom or region"))
    |> case do
      %{valid?: false, changes: changes} = changeset when changes == %{} ->
        %{changeset | action: :ignore}
      changeset ->
        changeset
    end
  end

  def valid_gtfs(%__MODULE__{resources: nil}), do: []
  def valid_gtfs(%__MODULE__{resources: r, type: "transport-statique"}), do: Enum.filter(r, &Resource.valid?/1)
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

  ## Private functions

  defp validate_mutual_exclusion(changeset, fields, error) do
    fields
    |> Enum.count(& not get_field(changeset, &1) in ["", nil])
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
end
