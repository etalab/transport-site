defmodule DB.DefaultToken do
  @moduledoc """
  Represents a default token for a contact.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset
  import Ecto.Query

  typed_schema "default_token" do
    belongs_to(:contact, DB.Contact)
    belongs_to(:token, DB.Token)
    timestamps(type: :utc_datetime_usec)
  end

  def base_query, do: from(df in __MODULE__, as: :default_token)

  def changeset(%__MODULE__{} = struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [:contact_id, :token_id])
    |> validate_required([:contact_id, :token_id])
    |> assoc_constraint(:token)
    |> assoc_constraint(:contact)
    |> unique_constraint([:contact_id])
  end
end
