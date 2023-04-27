defmodule DB.Contact do
  @moduledoc """
  Represents a contact/user
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.{Changeset, Query}

  @default_phone_number_region "FR"

  typed_schema "contact" do
    # Use `first_name` and `last_name` for real humans
    field(:first_name, :string)
    field(:last_name, :string)
    # Use `mailing_list_title` for mailing lists and similar
    field(:mailing_list_title, :string)
    field(:datagouv_user_id, :string)

    field(:organization, :string)
    field(:job_title, :string)
    field(:email, DB.Encrypted.Binary)
    # Should be used to search rows matching an email address
    # https://hexdocs.pm/cloak_ecto/install.html#usage
    field(:email_hash, Cloak.Ecto.SHA256)
    field(:phone_number, DB.Encrypted.Binary)
    field(:secondary_phone_number, DB.Encrypted.Binary)
    field(:last_login_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)

    has_many(:notification_subscriptions, DB.NotificationSubscription, on_delete: :delete_all)
  end

  def base_query, do: from(c in __MODULE__, as: :contact)

  def search(%{"q" => q}) do
    base_query()
    |> where([contact: c], c.organization == ^q)
    |> or_where(
      [contact: c],
      fragment(
        "to_tsvector('custom_french', concat(?, ' ', ?, ' ', ?)) @@  plainto_tsquery('custom_french', ?)",
        c.first_name,
        c.last_name,
        c.mailing_list_title,
        ^q
      )
    )
  end

  def search(%{}), do: base_query()

  def insert!(%{} = fields), do: %__MODULE__{} |> changeset(fields) |> DB.Repo.insert!()

  @doc """
  iex> display_name(%DB.Contact{first_name: "John", last_name: "Doe", mailing_list_title: nil})
  "John Doe"
  iex> display_name(%DB.Contact{first_name: nil, last_name: nil, mailing_list_title: "Service SIG"})
  "Service SIG"
  """
  def display_name(%__MODULE__{first_name: first_name, last_name: last_name, mailing_list_title: title} = object) do
    cond do
      is_human?(object) -> "#{first_name} #{last_name}"
      is_mailing_list?(object) -> title
    end
  end

  @doc """
  iex> is_human?(%DB.Contact{first_name: "John", last_name: "Doe", mailing_list_title: nil})
  true
  iex> is_human?(%DB.Contact{first_name: nil, last_name: nil, mailing_list_title: "Service SIG"})
  false
  """
  def is_human?(%__MODULE__{mailing_list_title: title}), do: is_nil(title)

  @doc """
  iex> is_mailing_list?(%DB.Contact{first_name: "John", last_name: "Doe", mailing_list_title: nil})
  false
  iex> is_mailing_list?(%DB.Contact{first_name: nil, last_name: nil, mailing_list_title: "Service SIG"})
  true
  """
  def is_mailing_list?(%__MODULE__{} = object), do: !is_human?(object)

  def changeset(struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [
      :first_name,
      :last_name,
      :mailing_list_title,
      :organization,
      :job_title,
      :email,
      :phone_number,
      :secondary_phone_number,
      :datagouv_user_id,
      :last_login_at
    ])
    |> trim_fields([:first_name, :last_name, :organization, :job_title])
    |> capitalize_fields([:first_name, :last_name])
    |> validate_required([:organization, :email])
    |> validate_format(:email, ~r/@/)
    |> validate_names_or_mailing_list_title()
    |> cast_phone_numbers()
    |> lowercase_email()
    |> put_hashed_fields()
    |> unique_constraint(:email_hash, error_key: :email, name: :contact_email_hash_index)
  end

  defp validate_names_or_mailing_list_title(%Ecto.Changeset{} = changeset) do
    case Enum.map(~w(first_name last_name mailing_list_title)a, &get_field(changeset, &1)) do
      [nil, nil, nil] ->
        add_error(changeset, :first_name, "You need to fill first_name and last_name OR mailing_list_title")

      [first_name, last_name, nil] when first_name != nil and last_name != nil ->
        changeset

      [nil, nil, title] when title != nil ->
        changeset

      _ ->
        add_error(changeset, :first_name, "You need to fill either first_name and last_name OR mailing_list_title")
    end
  end

  defp trim_fields(%Ecto.Changeset{} = changeset, fields) do
    fields
    |> Enum.reject(&(get_field(changeset, &1) == nil))
    |> Enum.reduce(changeset, fn field, changeset -> update_change(changeset, field, &String.trim/1) end)
  end

  defp capitalize_fields(%Ecto.Changeset{} = changeset, fields) do
    fields
    |> Enum.reject(&(get_field(changeset, &1) == nil))
    |> Enum.reduce(changeset, fn field, changeset -> update_change(changeset, field, &String.capitalize/1) end)
  end

  defp cast_phone_numbers(%Ecto.Changeset{} = changeset) do
    ~w(phone_number secondary_phone_number)a
    |> Enum.map_reduce(changeset, fn field, acc -> {nil, cast_phone_number(acc, field)} end)
    |> elem(1)
  end

  defp cast_phone_number(%Ecto.Changeset{} = changeset, field) when is_atom(field) do
    case get_field(changeset, field) do
      nil ->
        changeset

      phone_number_value ->
        case ExPhoneNumber.parse(phone_number_value, @default_phone_number_region) do
          {:ok, phone_number} -> parse_phone_number(changeset, phone_number, field)
          {:error, reason} -> add_error(changeset, field, reason)
        end
    end
  end

  defp parse_phone_number(%Ecto.Changeset{} = changeset, %ExPhoneNumber.Model.PhoneNumber{} = phone_number, field) do
    cond do
      not ExPhoneNumber.is_possible_number?(phone_number) ->
        add_error(changeset, field, "Phone number is not a possible number")

      not ExPhoneNumber.is_valid_number?(phone_number) ->
        add_error(changeset, field, "Phone number is not a valid number")

      true ->
        put_change(changeset, field, ExPhoneNumber.format(phone_number, :e164))
    end
  end

  defp lowercase_email(%Ecto.Changeset{} = changeset) do
    update_change(changeset, :email, &String.downcase/1)
  end

  defp put_hashed_fields(%Ecto.Changeset{} = changeset) do
    changeset |> put_change(:email_hash, get_field(changeset, :email))
  end
end
