defmodule DB.DatasetSubtype do
  @moduledoc """
  Represents dataset subtypes.
  A subtype has a parent_type (e.g., "public-transit") and a slug (e.g., "urban", "intercity").
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset
  use Gettext, backend: TransportWeb.Gettext

  typed_schema "dataset_subtype" do
    field(:parent_type, :string)
    field(:slug, :string)

    timestamps(type: :utc_datetime_usec)

    many_to_many(:datasets, DB.Dataset, join_through: "dataset_dataset_subtype", on_replace: :delete)
  end

  def changeset(%__MODULE__{} = struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [:parent_type, :slug])
    |> validate_required([:parent_type, :slug])
    |> unique_constraint([:parent_type, :slug])
  end

  @doc """
  Converts a subtype slug to a human-readable string.

  ## Examples

      iex> DB.DatasetSubtype.slug_to_str("urban")
      "Urbain"
  """
  @spec slug_to_str(binary()) :: binary()
  def slug_to_str("urban"), do: dgettext("page-shortlist", "Urban")
  def slug_to_str("intercity"), do: dgettext("page-shortlist", "Intercity")
  def slug_to_str("school"), do: dgettext("page-shortlist", "School transport")
  def slug_to_str("seasonal"), do: dgettext("page-shortlist", "Seasonal")
  def slug_to_str("zonal_drt"), do: dgettext("page-shortlist", "Demand responsive transport")
  def slug_to_str("bicycle"), do: dgettext("page-shortlist", "Bicycle")
  def slug_to_str("scooter"), do: dgettext("page-shortlist", "Scooter")
  def slug_to_str("carsharing"), do: dgettext("page-shortlist", "Carsharing")
  def slug_to_str("moped"), do: dgettext("page-shortlist", "Moped")
  def slug_to_str("freefloating"), do: dgettext("page-shortlist", "Free-floating")
end
