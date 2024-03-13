defmodule DB.DatasetFollower do
  @moduledoc """
  Represents contacts following datasets.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset

  typed_schema "dataset_followers" do
    belongs_to(:dataset, DB.Dataset)
    belongs_to(:contact, DB.Contact)
    field(:source, Ecto.Enum, values: [:datagouv])
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(%__MODULE__{} = struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [:dataset_id, :contact_id, :source])
    |> validate_required([:dataset_id, :contact_id, :source])
    |> assoc_constraint(:dataset)
    |> assoc_constraint(:contact)
    |> unique_constraint([:dataset_id, :contact_id])
  end
end
