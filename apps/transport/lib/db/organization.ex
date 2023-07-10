defmodule DB.Organization do
  @moduledoc """
  Represents an organization on data.gouv.fr
  """
  use TypedEctoSchema
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, []}

  typed_schema "organization" do
    field(:slug, :string)
    field(:name, :string)
    field(:acronym, :string)
    field(:logo, :string)
    field(:logo_thumbnail, :string)
    field(:badges, {:array, :map})
    field(:metrics, :map)
    field(:created_at, :utc_datetime_usec)

    many_to_many(:contacts, DB.Contact, join_through: "contacts_organizations", on_replace: :delete)
    has_many(:datasets, DB.Dataset)
  end

  def changeset(struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [:id, :slug, :name, :acronym, :logo, :logo_thumbnail, :badges, :metrics, :created_at])
    |> validate_required([:id, :slug, :name, :logo, :logo_thumbnail, :badges])
  end
end
