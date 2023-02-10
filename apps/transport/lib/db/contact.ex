defmodule DB.Contact do
  @moduledoc """
  Represents a contact/user
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @default_phone_number_region "FR"

  schema "contact" do
    field(:first_name, :string)
    field(:last_name, :string)
    field(:organization, :string)
    field(:job_title, :string)
    field(:email, DB.Encrypted.Binary)
    # Should be used to search rows matching an email address
    # https://hexdocs.pm/cloak_ecto/install.html#usage
    field(:email_hash, Cloak.Ecto.SHA256)
    field(:phone_number, DB.Encrypted.Binary)

    timestamps(type: :utc_datetime_usec)
  end

  def base_query, do: from(c in __MODULE__, as: :contact)

  def search(%{"q" => q}) do
    ilike = "%#{q}%"
    base_query() |> where([contact: c], ilike(c.last_name, ^ilike) or c.organization == ^q)
  end

  def search(%{}), do: base_query()

  def insert!(%{} = fields), do: %__MODULE__{} |> changeset(fields) |> DB.Repo.insert!()

  def changeset(struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [:first_name, :last_name, :organization, :job_title, :email, :phone_number])
    |> trim_fields([:first_name, :last_name, :organization, :job_title])
    |> validate_required([:first_name, :last_name, :organization, :email])
    |> validate_format(:email, ~r/@/)
    |> cast_phone_number()
    |> put_hashed_fields()
    |> unique_constraint(:email_hash, error_key: :email, name: :contact_email_hash_index)
  end

  defp trim_fields(%Ecto.Changeset{} = changeset, fields) do
    Enum.reduce(fields, changeset, fn field, changeset -> update_change(changeset, field, &String.trim/1) end)
  end

  defp cast_phone_number(%Ecto.Changeset{} = changeset) do
    case get_field(changeset, :phone_number) do
      nil ->
        changeset

      phone_number_value ->
        case ExPhoneNumber.parse(phone_number_value, @default_phone_number_region) do
          {:ok, phone_number} -> parse_phone_number(changeset, phone_number)
          {:error, reason} -> add_error(changeset, :phone_number, reason)
        end
    end
  end

  defp parse_phone_number(%Ecto.Changeset{} = changeset, %ExPhoneNumber.Model.PhoneNumber{} = phone_number) do
    cond do
      not ExPhoneNumber.is_possible_number?(phone_number) ->
        add_error(changeset, :phone_number, "Phone number is not a possible number")

      not ExPhoneNumber.is_valid_number?(phone_number) ->
        add_error(changeset, :phone_number, "Phone number is not a valid number")

      true ->
        put_change(changeset, :phone_number, ExPhoneNumber.format(phone_number, :e164))
    end
  end

  defp put_hashed_fields(%Ecto.Changeset{} = changeset) do
    changeset |> put_change(:email_hash, get_field(changeset, :email))
  end
end
