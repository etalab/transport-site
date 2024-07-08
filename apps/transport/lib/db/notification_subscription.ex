defmodule DB.NotificationSubscription do
  @moduledoc """
  Represents a subscription to a notification type for a `DB.Contact`
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.{Changeset, Query}
  import Transport.NotificationReason

  typed_schema "notification_subscription" do
    field(:reason, Ecto.Enum, values: all_reasons())

    # The subscription source:
    # - `:admin`: created by an admin from the backoffice
    # - `:user`: by the user using self-service tools
    # - `automation:<slug>`: created by the system, the slug adds more details about the source
    field(:source, Ecto.Enum,
      values: [:admin, :user, :"automation:promote_producer_space", :"automation:migrate_from_reuser_to_producer"]
    )

    field(:role, Ecto.Enum, values: possible_roles())

    belongs_to(:contact, DB.Contact)
    belongs_to(:dataset, DB.Dataset)

    timestamps(type: :utc_datetime_usec)
  end

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

  @spec subscriptions_for_reason_dataset_and_role(atom(), DB.Dataset.t(), Transport.NotificationReason.role()) :: [
          __MODULE__.t()
        ]
  def subscriptions_for_reason_dataset_and_role(reason, %DB.Dataset{id: dataset_id}, role) do
    base_query()
    |> preload([:contact])
    |> where(
      [notification_subscription: ns],
      ns.reason == ^reason and ns.dataset_id == ^dataset_id and ns.role == ^role
    )
    |> DB.Repo.all()
  end

  @spec subscriptions_for_reason_and_role(atom(), Transport.NotificationReason.role()) :: [__MODULE__.t()]
  def subscriptions_for_reason_and_role(reason, role) do
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

  @spec subscriptions_for_dataset_and_role(DB.Dataset.t(), Transport.NotificationReason.role()) :: [__MODULE__.t()]
  def subscriptions_for_dataset_and_role(%DB.Dataset{id: dataset_id}, role) do
    base_query()
    |> preload([:contact])
    |> where([notification_subscription: ns], ns.dataset_id == ^dataset_id and ns.role == ^role)
    |> DB.Repo.all()
  end

  defp validate_reason_is_allowed_for_subscriptions(changeset) do
    reason = get_field(changeset, :reason)

    if reason in subscribable_reasons() do
      changeset
    else
      add_error(changeset, :reason, "is not allowed for subscription")
    end
  end

  #  The two following functions are also used for the DB.Notification chaneset!
  def validate_reason_by_role(changeset) do
    role = get_field(changeset, :role)
    reason = get_field(changeset, :reason)

    if reason in reasons_for_role(role) do
      changeset
    else
      add_error(changeset, :reason, "is not allowed for the given role")
    end
  end

  def validate_reason_by_scope(changeset) do
    reason = get_field(changeset, :reason)
    dataset_id = get_field(changeset, :dataset_id)

    cond do
      dataset_id == nil && reason in platform_wide_reasons() -> changeset
      dataset_id != nil && reason in reasons_related_to_datasets() -> changeset
      true -> add_error(changeset, :reason, "is not allowed for the given dataset presence")
    end
  end
end
