defmodule DB.NotificationSubscription do
  @moduledoc """
  Represents a subscription to a notification type for a `DB.Contact`
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.{Changeset, Query}
  import TransportWeb.Gettext, only: [dgettext: 2]

  @possible_roles [:producer, :reuser]

  # Rules explanations for reasons:
  # 1. scope: reasons are scoped either to a specific dataset or to the platform.
  # (In some cases for reusers, «platform» means scoped to followed datasets, not all datasets.)
  # 2. possible roles: reasons can be subscribed to by either producers or reusers.
  # 3. disallow_subscription: some reasons can’t be subscribed to,
  # but they exist because they are valid for notifications.
  # (In this case, it’s the platform that decides when to send them, without the user subscribing to them.)
  # 4. hide_from_user: some reasons are hidden from the user interface, but can be subscribed in CLI or backoffice.

  @reasons_rules %{
    expiration: %{
      scope: :dataset,
      possible_roles: [:producer, :reuser]
    },
    dataset_with_error: %{
      scope: :dataset,
      possible_roles: [:producer, :reuser]
    },
    resource_unavailable: %{
      scope: :dataset,
      possible_roles: [:producer, :reuser]
    },
    resources_changed: %{
      scope: :dataset,
      possible_roles: [:reuser]
    },
    new_dataset: %{
      scope: :platform,
      possible_roles: [:reuser]
    },
    datasets_switching_climate_resilience_bill: %{
      scope: :platform,
      possible_roles: [:reuser],
      hide_from_user: [:reuser]
    },
    daily_new_comments: %{
      scope: :platform,
      possible_roles: [:producer, :reuser],
      hide_from_user: [:producer]
    },
    dataset_now_on_nap: %{
      scope: :dataset,
      possible_roles: [:producer],
      disallow_subscription: true
    },
    periodic_reminder_producers: %{
      scope: :platform,
      possible_roles: [:producer],
      disallow_subscription: true
    },
    promote_producer_space: %{
      scope: :platform,
      possible_roles: [:producer],
      disallow_subscription: true
    },
    promote_reuser_space: %{
      scope: :platform,
      possible_roles: [:reuser],
      disallow_subscription: true
    },
    warn_user_inactivity: %{
      scope: :platform,
      possible_roles: [:producer, :reuser],
      disallow_subscription: true
    }
  }

  @all_reasons @reasons_rules |> Map.keys()

  # https://elixirforum.com/t/using-module-attributes-in-typespec-definitions-to-reduce-duplication/42374/2
  types = Enum.reduce(@possible_roles, &{:|, [], [&1, &2]})
  @type role :: unquote(types)
  types = Enum.reduce(@all_reasons, &{:|, [], [&1, &2]})
  @type reason :: unquote(types)

  typed_schema "notification_subscription" do
    field(:reason, Ecto.Enum, values: @all_reasons)

    # The subscription source:
    # - `:admin`: created by an admin from the backoffice
    # - `:user`: by the user using self-service tools
    # - `automation:<slug>`: created by the system, the slug adds more details about the source
    field(:source, Ecto.Enum,
      values: [:admin, :user, :"automation:promote_producer_space", :"automation:migrate_from_reuser_to_producer"]
    )

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

  def insert(%{} = fields), do: %__MODULE__{} |> changeset(fields) |> DB.Repo.insert()
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
    |> validate_reason_is_allowed_for_subscriptions()
    |> validate_reason_by_role()
    |> validate_reason_by_scope()
  end

  defp maybe_assoc_constraint_dataset(%Ecto.Changeset{} = changeset) do
    if is_nil(get_field(changeset, :dataset_id)) do
      changeset
    else
      changeset |> assoc_constraint(:dataset)
    end
  end

  @spec possible_reasons :: [reason()]
  def possible_reasons, do: @all_reasons

  @doc """
  iex> subscribable_reasons() |> MapSet.new()
  MapSet.new([:daily_new_comments, :dataset_with_error, :datasets_switching_climate_resilience_bill, :expiration, :new_dataset, :resource_unavailable, :resources_changed])
  """
  @spec subscribable_reasons :: [reason()]
  def subscribable_reasons do
    @reasons_rules
    |> Map.filter(fn
      {_, %{disallow_subscription: true}} -> false
      _ -> true
    end)
    |> Map.keys()
  end

  def unsuscribable_reasons do
    @reasons_rules
    |> Map.filter(fn
      {_, %{disallow_subscription: true}} -> true
      _ -> false
    end)
    |> Map.keys()
  end

  @spec possible_roles() :: [role()]
  def possible_roles, do: @possible_roles

  @doc """
  iex> reasons_for_role(:reuser) |> MapSet.new()
  MapSet.new([:daily_new_comments, :dataset_with_error, :datasets_switching_climate_resilience_bill, :expiration, :new_dataset, :promote_reuser_space, :resource_unavailable, :resources_changed, :warn_user_inactivity])
  """
  @spec reasons_for_role(role()) :: [reason()]
  def reasons_for_role(role) do
    @reasons_rules
    |> Map.filter(fn
      {_, %{possible_roles: possible_roles}} -> role in possible_roles
      _ -> false
    end)
    |> Map.keys()
  end

  @doc """
  iex> hidden_reasons_for_role(:reuser)
  [:datasets_switching_climate_resilience_bill]
  """
  @spec hidden_reasons_for_role(role()) :: [reason()]
  def hidden_reasons_for_role(role) do
    @reasons_rules
    |> Map.filter(fn
      {_, %{hide_from_user: hide_from_user}} -> role in hide_from_user
      _ -> false
    end)
    |> Map.keys()
  end

  @spec reasons_related_to_datasets :: [reason()]
  def reasons_related_to_datasets do
    @reasons_rules
    |> Map.filter(fn
      {_, %{scope: :dataset}} -> true
      _ -> false
    end)
    |> Map.keys()
  end

  @spec platform_wide_reasons :: [reason()]
  def platform_wide_reasons do
    @reasons_rules
    |> Map.filter(fn
      {_, %{scope: :platform}} -> true
      _ -> false
    end)
    |> Map.keys()
  end

  @doc """
  iex> subscribable_reasons_related_to_datasets(:reuser) != subscribable_reasons_related_to_datasets(:producer)
  true
  """
  @spec subscribable_reasons_related_to_datasets(role()) :: [reason()]
  def subscribable_reasons_related_to_datasets(role) do
    MapSet.new(reasons_related_to_datasets())
    |> MapSet.intersection(MapSet.new(reasons_for_role(role)))
    |> MapSet.intersection(MapSet.new(subscribable_reasons()))
    |> MapSet.to_list()
  end

  @doc """
  iex> subscribable_platform_wide_reasons(:reuser) != subscribable_platform_wide_reasons(:producer)
  true
  iex> subscribable_platform_wide_reasons(:producer)
  [:daily_new_comments]
  iex> subscribable_platform_wide_reasons(:reuser)
  [:daily_new_comments, :datasets_switching_climate_resilience_bill, :new_dataset]
  """
  @spec subscribable_platform_wide_reasons(role()) :: [reason()]
  def subscribable_platform_wide_reasons(role) do
    platform_wide_reasons()
    |> MapSet.new()
    |> MapSet.intersection(MapSet.new(reasons_for_role(role)))
    |> MapSet.intersection(MapSet.new(subscribable_reasons()))
    |> MapSet.to_list()
  end

  @doc """
  iex> shown_subscribable_platform_wide_reasons(:reuser)
  [:daily_new_comments, :new_dataset]
  """
  @spec shown_subscribable_platform_wide_reasons(role()) :: [reason()]
  def shown_subscribable_platform_wide_reasons(role) do
    subscribable_platform_wide_reasons(role) -- hidden_reasons_for_role(role)
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

  def producer_subscriptions_for_datasets(dataset_ids, contact_id) do
    DB.NotificationSubscription.base_query()
    |> preload(:contact)
    |> where(
      [notification_subscription: ns],
      ns.role == :producer and
        ns.dataset_id in ^dataset_ids and
        ns.reason in ^subscribable_reasons_related_to_datasets(:producer)
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

  @doc """
  The following configuration map for translations can’t be merged in the global configuration map
  because module attributes are compiled and not evaluated, which would freeze the translation to default locale.
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
        periodic_reminder_producers: dgettext("notification_subscription", "periodic_reminder_producers"),
        promote_producer_space: dgettext("notification_subscription", "promote_producer_space"),
        promote_reuser_space: dgettext("notification_subscription", "promote_reuser_space"),
        warn_user_inactivity: dgettext("notification_subscription", "warn_user_inactivity")
      },
      reason
    )
  end

  defp validate_reason_is_allowed_for_subscriptions(changeset) do
    reason = get_field(changeset, :reason)

    if reason in subscribable_reasons() do
      changeset
    else
      add_error(changeset, :reason, "is not allowed for subscription")
    end
  end

  defp validate_reason_by_role(changeset) do
    role = get_field(changeset, :role)
    reason = get_field(changeset, :reason)

    if reason in reasons_for_role(role) do
      changeset
    else
      add_error(changeset, :reason, "is not allowed for the given role")
    end
  end

  defp validate_reason_by_scope(changeset) do
    reason = get_field(changeset, :reason)
    dataset_id = get_field(changeset, :dataset_id)

    cond do
      dataset_id == nil && reason in platform_wide_reasons() -> changeset
      dataset_id != nil && reason in reasons_related_to_datasets() -> changeset
      true -> add_error(changeset, :reason, "is not allowed for the given dataset presence")
    end
  end
end
