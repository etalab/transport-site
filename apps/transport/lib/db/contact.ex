defmodule DB.Contact do
  @moduledoc """
  Represents a contact/user
  A contact is created or updated each time a user logs in, see session controller.
  Update through session controller includes the last login date and the organizations the user is part of.
  Transport.Jobs.UpdateContactsJob also updates regularly the contacts.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.{Changeset, Query}

  @default_phone_number_region "FR"
  @default_org_name "Inconnue"

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
    many_to_many(:organizations, DB.Organization, join_through: "contacts_organizations", on_replace: :delete)
    many_to_many(:followed_datasets, DB.Dataset, join_through: "dataset_followers", on_replace: :delete)
    has_many(:user_feedbacks, DB.UserFeedback, on_delete: :nilify_all)
  end

  def base_query, do: from(c in __MODULE__, as: :contact)

  def search(%{"q" => q}) do
    ilike_search = "%#{safe_like_pattern(q)}%"

    base_query()
    |> where([contact: c], ilike(c.organization, ^ilike_search))
    |> or_where([contact: c], fragment("unaccent(?) ilike unaccent(?)", c.last_name, ^ilike_search))
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

  @doc """
  Make sure a string that will be passed to `like` or `ilike` is safe.

  See https://elixirforum.com/t/secure-ecto-like-queries/31265
  iex> safe_like_pattern("I love %like_injections%\\!")
  "I love likeinjections!"
  """
  def safe_like_pattern(value) do
    String.replace(value, ["\\", "%", "_"], "")
  end

  def insert!(%{} = fields), do: %__MODULE__{} |> changeset(fields) |> DB.Repo.insert!()

  @doc """
  iex> display_name(%DB.Contact{first_name: "John", last_name: "Doe", mailing_list_title: nil})
  "John Doe"
  iex> display_name(%DB.Contact{first_name: nil, last_name: nil, mailing_list_title: "Service SIG"})
  "Service SIG"
  """
  def display_name(%__MODULE__{first_name: first_name, last_name: last_name, mailing_list_title: title} = object) do
    cond do
      human?(object) -> "#{first_name} #{last_name}"
      mailing_list?(object) -> title
    end
  end

  @doc """
  iex> human?(%DB.Contact{first_name: "John", last_name: "Doe", mailing_list_title: nil})
  true
  iex> human?(%DB.Contact{first_name: nil, last_name: nil, mailing_list_title: "Service SIG"})
  false
  """
  def human?(%__MODULE__{mailing_list_title: title}), do: is_nil(title)

  @doc """
  iex> mailing_list?(%DB.Contact{first_name: "John", last_name: "Doe", mailing_list_title: nil})
  false
  iex> mailing_list?(%DB.Contact{first_name: nil, last_name: nil, mailing_list_title: "Service SIG"})
  true
  """
  def mailing_list?(%__MODULE__{} = object), do: !human?(object)

  def changeset(struct, attrs \\ %{}) do
    struct
    |> DB.Repo.preload([:organizations])
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
    |> validate_required([:email])
    |> validate_format(:email, ~r/@/)
    |> validate_names_or_mailing_list_title()
    |> cast_phone_numbers()
    |> lowercase_email()
    |> put_hashed_fields()
    |> unique_constraint(:email_hash, error_key: :email, name: :contact_email_hash_index)
    |> save_organizations(attrs)
    |> cast_organization()
  end

  defp save_organizations(%Ecto.Changeset{} = changeset, %{} = attrs)
       when is_map_key(attrs, "organizations") or is_map_key(attrs, :organizations) do
    # Update organizations only when the key is present in the changes.
    # Passing an empty list would delete all orgs for the contact
    changeset
    |> put_assoc(:organizations, attrs |> organizations() |> Enum.map(&DB.Organization.changeset(find_org(&1), &1)))
  end

  defp save_organizations(%Ecto.Changeset{} = changeset, %{}), do: changeset

  defp cast_organization(%Ecto.Changeset{changes: changes} = changeset) when changes == %{}, do: changeset

  defp cast_organization(%Ecto.Changeset{} = changeset) do
    case {get_field(changeset, :organization), get_field(changeset, :organizations)} do
      {value, _} when is_binary(value) and value != @default_org_name ->
        put_change(changeset, :organization, value)

      {_, orgs} when is_list(orgs) ->
        put_change(changeset, :organization, organization_name(orgs))
    end
  end

  @doc """
  The best organization name possible for a contact.

  iex> organization_name([])
  "Inconnue"
  iex> organization_name([%DB.Organization{name: "1", badges: []}, %DB.Organization{name: "2", badges: []}])
  "1"
  iex> organization_name([%DB.Organization{name: "1", badges: []}, %DB.Organization{name: "2", badges: [%{"kind" => "certified"}]}])
  "2"
  """
  def organization_name([]), do: @default_org_name

  def organization_name(orgs) do
    certified_orgs =
      Enum.filter(orgs, fn %DB.Organization{badges: badges} -> %{"kind" => "certified"} in badges end)

    case certified_orgs do
      [] -> orgs |> List.first() |> Map.fetch!(:name)
      result -> result |> List.first() |> Map.fetch!(:name)
    end
  end

  defp organizations(%{"organizations" => orgs}), do: orgs
  defp organizations(%{organizations: orgs}), do: orgs

  defp find_org(%{"id" => id}), do: DB.Repo.get(DB.Organization, id) || %DB.Organization{}
  defp find_org(%{id: id}), do: DB.Repo.get(DB.Organization, id) || %DB.Organization{}
  defp find_org(%{}), do: %DB.Organization{}

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
    |> Enum.reduce(changeset, fn field, changeset -> update_change(changeset, field, &title_case/1) end)
  end

  @doc """
  iex> title_case("Antoine")
  "Antoine"
  iex> title_case("antoine")
  "Antoine"
  iex> title_case("jean marie")
  "Jean Marie"
  iex> title_case("jean-marie")
  "Jean-Marie"
  iex> title_case("Jean Marie")
  "Jean Marie"
  iex> title_case("Mélo")
  "Mélo"
  iex> title_case("")
  ""
  """
  def title_case(string) do
    string |> capitalize_per_word("-") |> capitalize_per_word(" ")
  end

  defp capitalize_per_word(string, split_join_char) do
    string
    |> String.split(split_join_char)
    |> Enum.map_join(split_join_char, &uppercase_first/1)
  end

  defp uppercase_first(string) do
    # Can't use `String.capitalize/2` because it lowercases the rest of the string
    {first, rest} = String.split_at(string, 1)
    String.upcase(first) <> rest
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

  @doc """
  A list of contact_ids for contacts who are members of the transport.data.gouv.fr's organization.

  This list is cached because it is very stable over time and we need it for multiple
  Oban jobs executed in parallel or one after another.
  Used for now to exclude transport.data.gouv.fr members
  when showing to a producer who are his fellow producers subscribed to notifications.
  """
  @spec admin_contact_ids() :: [integer()]
  def admin_contact_ids do
    Transport.Cache.fetch(
      to_string(__MODULE__) <> ":admin_contact_ids",
      fn -> Enum.map(admin_contacts(), & &1.id) end,
      :timer.seconds(60)
    )
  end

  @doc """
  Fetches `DB.Contact` who are members of the transport.data.gouv.fr's organization.
  """
  @spec admin_contacts() :: [DB.Contact.t()]
  def admin_contacts do
    pan_org_name = Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)

    DB.Organization.base_query()
    |> preload(:contacts)
    |> where([organization: o], o.name == ^pan_org_name)
    |> DB.Repo.one!()
    |> Map.fetch!(:contacts)
  end

  @doc """
  Fetches `DB.Contact` that didn't log in since a given datetime.
  """
  @spec list_inactive_contacts(DateTime.t()) :: [DB.Contact.t()]
  def list_inactive_contacts(%DateTime{} = threshold) do
    base_query()
    |> where([contact: c], c.last_login_at < ^threshold)
    |> order_by(asc: :last_login_at)
    |> DB.Repo.all()
  end

  @doc """
  Delete `DB.Contact` that didn't log in since a given datetime.
  """
  @spec delete_inactive_contacts(DateTime.t()) :: :ok
  def delete_inactive_contacts(%DateTime{} = threshold) do
    list_inactive_contacts(threshold) |> Enum.each(&DB.Repo.delete/1)
  end
end

# See https://hexdocs.pm/swoosh/Swoosh.Email.Recipient.html
defimpl Swoosh.Email.Recipient, for: DB.Contact do
  def format(%DB.Contact{email: email} = contact) do
    {DB.Contact.display_name(contact), email}
  end
end
