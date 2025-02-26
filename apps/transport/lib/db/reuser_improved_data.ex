defmodule DB.ReuserImprovedData do
  @moduledoc """
  Represents improved static data shared by reusers.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset
  import Ecto.Query

  typed_schema "reuser_improved_data" do
    belongs_to(:dataset, DB.Dataset)
    belongs_to(:resource, DB.Resource)
    belongs_to(:contact, DB.Contact)
    belongs_to(:organization, DB.Organization, type: :string)
    field(:download_url, :string)
    timestamps(type: :utc_datetime_usec)
  end

  def base_query, do: from(rm in __MODULE__, as: :reuser_improved_data)

  def changeset(%__MODULE__{} = struct, attrs \\ %{}) do
    fields = [:dataset_id, :resource_id, :contact_id, :organization_id, :download_url]

    struct
    |> cast(attrs, fields)
    |> validate_required(fields)
    |> assoc_constraint(:dataset)
    |> assoc_constraint(:resource)
    |> assoc_constraint(:contact)
    |> assoc_constraint(:organization)
    |> unique_constraint([:resource_id, :organization_id])
  end
end
