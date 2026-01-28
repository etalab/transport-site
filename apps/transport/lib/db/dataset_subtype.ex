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
  @spec slug_to_str(binary()) :: binary() | nil
  def slug_to_str(slug) when is_binary(slug) do
    case slug do
      "urban" -> dgettext("page-shortlist", "Urban")
      "intercity" -> dgettext("page-shortlist", "Intercity")
      "school" -> dgettext("page-shortlist", "School transport")
      "seasonal" -> dgettext("page-shortlist", "Seasonal")
      "zonal_drt" -> dgettext("page-shortlist", "Demand responsive transport")
      "bicycle" -> dgettext("page-shortlist", "Bicycle")
      "scooter" -> dgettext("page-shortlist", "Scooter")
      "carsharing" -> dgettext("page-shortlist", "Carsharing")
      "moped" -> dgettext("page-shortlist", "Moped")
      "freefloating" -> dgettext("page-shortlist", "Free-floating")
    end
  end

  def slug_to_str(_), do: nil
end
