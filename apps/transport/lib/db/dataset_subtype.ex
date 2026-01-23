defmodule DB.DatasetSubtype do
  @moduledoc """
  Represents dataset subtypes.
  A subtype has a parent_type (e.g., "public-transit") and a slug (e.g., "urban", "intercity").
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset

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
end
