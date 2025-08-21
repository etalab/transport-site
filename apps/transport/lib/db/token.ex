defmodule DB.Token do
  @moduledoc """
  Represents user tokens to access data while being authenticated.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset
  import Ecto.Query

  @token_secret_length 32

  typed_schema "token" do
    field(:name, :string)
    field(:secret, DB.Encrypted.Binary)
    # Should be used to search rows matching a secret
    # https://hexdocs.pm/cloak_ecto/install.html#usage
    field(:secret_hash, Cloak.Ecto.SHA256)
    belongs_to(:contact, DB.Contact)
    belongs_to(:organization, DB.Organization, type: :string)
    many_to_many(:default_for_contacts, DB.Contact, join_through: "default_token")
    timestamps(type: :utc_datetime_usec)
  end

  def base_query, do: from(t in __MODULE__, as: :token)

  def personal_token?(%__MODULE__{organization_id: nil}), do: true
  def personal_token?(%__MODULE__{}), do: false

  def changeset(%__MODULE__{} = struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [:name, :contact_id, :organization_id])
    |> validate_required([:name, :contact_id])
    |> assoc_constraint(:contact)
    |> organization_id()
    |> generate_secret()
    |> put_hashed_fields()
  end

  def organization_id(%Ecto.Changeset{} = changeset) do
    case get_field(changeset, :organization_id) do
      nil ->
        changeset

      _ ->
        changeset
        |> assoc_constraint(:organization)
        |> unique_constraint([:organization_id, :name])
    end
  end

  defp generate_secret(%Ecto.Changeset{} = changeset) do
    changeset
    |> put_change(:secret, :crypto.strong_rand_bytes(@token_secret_length) |> Base.url_encode64(padding: false))
  end

  defp put_hashed_fields(%Ecto.Changeset{} = changeset) do
    changeset |> put_change(:secret_hash, get_field(changeset, :secret))
  end
end
