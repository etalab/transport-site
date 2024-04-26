defmodule DB.NotificationSubscription do
  @moduledoc """
  Represents a subscription to a notification type for a `DB.Contact`
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.{Changeset, Query}
  import TransportWeb.Gettext, only: [dgettext: 2]

  # These notification reasons are required to have a `dataset_id` set
  @reasons_related_to_datasets [:expiration, :dataset_with_error, :resource_unavailable]
  # These notification reasons are also required to have a `dataset_id` set
  # but are not made visible to users
  @hidden_reasons_related_to_datasets [:dataset_now_on_nap, :resources_changed]
  # These notification reasons are *not* linked to a specific dataset, `dataset_id` should be nil
  @platform_wide_reasons [:new_dataset, :datasets_switching_climate_resilience_bill, :daily_new_comments]
  # These notifications should not be linked to a dataset and should be hidden from users: they
  # should not be able to subscribe to these reasons.
  @hidden_platform_wide_reasons [:periodic_reminder_producers]

  @all_reasons @reasons_related_to_datasets ++
                 @platform_wide_reasons ++
                 @hidden_reasons_related_to_datasets ++
                 @hidden_platform_wide_reasons

  @possible_roles [:producer, :reuser]

  # https://elixirforum.com/t/using-module-attributes-in-typespec-definitions-to-reduce-duplication/42374/2
  types = Enum.reduce(@possible_roles, &{:|, [], [&1, &2]})
  @type role :: unquote(types)
  types = Enum.reduce(@all_reasons, &{:|, [], [&1, &2]})
  @type reason :: unquote(types)

  typed_schema "notification_subscription" do
    field(:reason, Ecto.Enum, values: @all_reasons)

    # Useful to know if the subscription has been created by an admin
    # from the backoffice (`:admin`) or by the user (`:user`)
    field(:source, Ecto.Enum, values: [:admin, :user])
    field(:role, Ecto.Enum, values: @possible_roles)

    belongs_to(:contact, DB.Contact)
    belongs_to(:dataset, DB.Dataset)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  This method provides a consistent manner to reference a `DB.NotificationSubscription.reason`.
  This is useful when searching for code related to a reason, as it allows you to easily
  find all references to a particular reason.
  *
  The custom type `reason` helps us be safer at compile time, by preventing us from accidentally
  passing in an invalid reason value.
  """
  @spec reason(reason()) :: reason()
  def reason(reason) when reason in @all_reasons, do: reason

  def base_query, do: from(ns in __MODULE__, as: :notification_subscription)

  def join_with_contact(query) do
    query
    |> join(:inner, [notification_subscription: ns], c in DB.Contact, on: ns.contact_id == c.id, as: :contact)
  end

  def insert!(%{} = fields), do: %__MODULE__{} |> changeset(fields) |> DB.Repo.insert!()

  def changeset(struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [:contact_id, :dataset_id, :reason, :source, :role])
    |> validate_required([:contact_id, :reason, :source, :role])
    |> assoc_constraint(:contact)
    |> maybe_assoc_constraint_dataset()
    |> unique_constraint([:contact_id, :dataset_id, :reason],
      name: :notification_subscription_contact_id_dataset_id_reason_index
    )
    |> validate_reason_by_role_and_dataset_presence()
  end

  defp maybe_assoc_constraint_dataset(%Ecto.Changeset{} = changeset) do
    if get_field(changeset, :dataset_id) do
      changeset |> assoc_constraint(:dataset)
    else
      changeset
    end
  end

  @spec reasons_related_to_datasets :: [reason()]
  def reasons_related_to_datasets, do: @reasons_related_to_datasets

  @doc """
  iex> reasons_related_to_datasets(:reuser) != reasons_related_to_datasets(:producer)
  true
  """
  @spec reasons_related_to_datasets(role()) :: [reason()]
  def reasons_related_to_datasets(:reuser) do
    reasons_related_to_datasets() ++ [reason(:resources_changed)]
  end

  def reasons_related_to_datasets(:producer), do: reasons_related_to_datasets()

  @spec platform_wide_reasons :: [reason()]
  def platform_wide_reasons, do: @platform_wide_reasons

  @doc """
  iex> platform_wide_reasons(:reuser) != platform_wide_reasons(:producer)
  true
  iex> platform_wide_reasons(:producer)
  [:new_dataset, :datasets_switching_climate_resilience_bill, :daily_new_comments]
  iex> platform_wide_reasons(:reuser)
  [:new_dataset, :daily_new_comments]
  """
  @spec platform_wide_reasons(role()) :: [reason()]
  def platform_wide_reasons(:reuser) do
    Enum.reject(platform_wide_reasons(), &(&1 == reason(:datasets_switching_climate_resilience_bill)))
  end

  def platform_wide_reasons(:producer), do: @platform_wide_reasons

  @spec possible_reasons :: [reason()]
  def possible_reasons, do: @all_reasons

  @spec subscriptions_for_reason(atom()) :: [__MODULE__.t()]
  def subscriptions_for_reason(reason) do
    base_query()
    |> preload([:contact])
    |> where([notification_subscription: ns], ns.reason == ^reason and is_nil(ns.dataset_id))
    |> DB.Repo.all()
  end

  @spec subscriptions_for_reason(atom(), DB.Dataset.t()) :: [__MODULE__.t()]
  def subscriptions_for_reason(reason, %DB.Dataset{id: dataset_id}) do
    base_query()
    |> preload([:contact])
    |> where([notification_subscription: ns], ns.reason == ^reason and ns.dataset_id == ^dataset_id)
    |> DB.Repo.all()
  end

  @spec subscriptions_for_reason_dataset_and_role(atom(), DB.Dataset.t(), role()) :: [__MODULE__.t()]
  def subscriptions_for_reason_dataset_and_role(reason, %DB.Dataset{id: dataset_id}, role)
      when role in @possible_roles do
    base_query()
    |> preload([:contact])
    |> where(
      [notification_subscription: ns],
      ns.reason == ^reason and ns.dataset_id == ^dataset_id and ns.role == ^role
    )
    |> DB.Repo.all()
  end

  @spec subscriptions_for_reason_and_role(atom(), role()) :: [__MODULE__.t()]
  def subscriptions_for_reason_and_role(reason, role) when role in @possible_roles do
    base_query()
    |> preload([:contact])
    |> where([notification_subscription: ns], ns.reason == ^reason and is_nil(ns.dataset_id) and ns.role == ^role)
    |> DB.Repo.all()
  end

  @spec subscriptions_for_dataset(DB.Dataset.t()) :: [__MODULE__.t()]
  def subscriptions_for_dataset(%DB.Dataset{id: dataset_id}) do
    base_query()
    |> preload([:contact])
    |> where([notification_subscription: ns], ns.dataset_id == ^dataset_id)
    |> DB.Repo.all()
  end

  def producer_subscriptions_for_datasets(dataset_ids, contact_id) do
    DB.NotificationSubscription.base_query()
    |> preload(:contact)
    |> where(
      [notification_subscription: ns],
      ns.role == :producer and
        ns.dataset_id in ^dataset_ids and
        ns.reason in ^reasons_related_to_datasets(:producer)
    )
    |> DB.Repo.all()
    # transport.data.gouv.fr's members who are subscribed as "producers" shouldn't be included.
    # they are dogfooding the feature
    |> filter_out_admin_subscription(contact_id)
    # Alphabetical order (and helps tests)
    |> Enum.sort_by(&DB.Contact.display_name(&1.contact))
  end

  def filter_out_admin_subscription(subscriptions, contact_id) do
    admin_ids = DB.Contact.admin_contact_ids()

    if contact_id in admin_ids do
      subscriptions
    else
      Enum.reject(subscriptions, fn %DB.NotificationSubscription{contact: %DB.Contact{id: contact_id}} ->
        contact_id in admin_ids
      end)
    end
  end

  @spec subscriptions_for_dataset_and_role(DB.Dataset.t(), role()) :: [__MODULE__.t()]
  def subscriptions_for_dataset_and_role(%DB.Dataset{id: dataset_id}, role) when role in @possible_roles do
    base_query()
    |> preload([:contact])
    |> where([notification_subscription: ns], ns.dataset_id == ^dataset_id and ns.role == ^role)
    |> DB.Repo.all()
  end

  @spec subscriptions_to_emails([__MODULE__.t()]) :: [binary()]
  def subscriptions_to_emails(subscriptions) do
    subscriptions |> Enum.map(& &1.contact.email)
  end

  @doc """
  iex> possible_reasons() |> Enum.each(&reason_to_str/1)
  :ok
  """
  @spec reason_to_str(reason() | binary()) :: binary()
  def reason_to_str(reason) when is_binary(reason), do: reason |> String.to_existing_atom() |> reason_to_str()

  def reason_to_str(reason) do
    Map.fetch!(
      %{
        expiration: dgettext("notification_subscription", "expiration"),
        dataset_with_error: dgettext("notification_subscription", "dataset_with_error"),
        resource_unavailable: dgettext("notification_subscription", "resource_unavailable"),
        dataset_now_on_nap: dgettext("notification_subscription", "dataset_now_on_nap"),
        new_dataset: dgettext("notification_subscription", "new_dataset"),
        datasets_switching_climate_resilience_bill:
          dgettext("notification_subscription", "datasets_switching_climate_resilience_bill"),
        daily_new_comments: dgettext("notification_subscription", "daily_new_comments"),
        resources_changed: dgettext("notification_subscription", "resources_changed"),
        periodic_reminder_producers: dgettext("notification_subscription", "periodic_reminder_producers")
      },
      reason
    )
  end

  defp validate_reason_by_role_and_dataset_presence(changeset) do
    role = get_field(changeset, :role)
    reason = get_field(changeset, :reason)
    dataset_id = get_field(changeset, :dataset_id)

    valid_reasons =
      case {role, dataset_id} do
        {:producer, nil} -> platform_wide_reasons(:producer) ++ [:periodic_reminder_producers]
        {:producer, _id} -> reasons_related_to_datasets(:producer)
        {:reuser, nil} -> platform_wide_reasons(:reuser)
        {:reuser, _id} -> reasons_related_to_datasets(:reuser)
        _ -> @all_reasons
      end

    if reason in valid_reasons do
      changeset
    else
      add_error(changeset, :reason, "is not valid for the given role and dataset presence")
    end
  end
end
