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

  typed_schema "notification_subscription" do
    field(:reason, Ecto.Enum,
      values: @reasons_related_to_datasets ++ @platform_wide_reasons ++ @hidden_reasons_related_to_datasets
    )

    field(:source, Ecto.Enum, values: [:admin, :user])
    field(:role, Ecto.Enum, values: [:producer, :reuser])

    belongs_to(:contact, DB.Contact)
    belongs_to(:dataset, DB.Dataset)

    timestamps(type: :utc_datetime_usec)
  end

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
  end

  defp maybe_assoc_constraint_dataset(%Ecto.Changeset{} = changeset) do
    if get_field(changeset, :reason) in (reasons_related_to_datasets() ++ @hidden_reasons_related_to_datasets) do
      changeset |> validate_required(:dataset_id) |> assoc_constraint(:dataset)
    else
      changeset |> validate_inclusion(:dataset_id, [nil])
    end
  end

  @spec reasons_related_to_datasets :: [atom()]
  def reasons_related_to_datasets, do: @reasons_related_to_datasets

  @spec platform_wide_reasons :: [atom()]
  def platform_wide_reasons, do: @platform_wide_reasons

  @spec possible_reasons :: [atom()]
  def possible_reasons,
    do: reasons_related_to_datasets() ++ platform_wide_reasons() ++ @hidden_reasons_related_to_datasets

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

  @spec subscriptions_for_dataset(DB.Dataset.t()) :: [__MODULE__.t()]
  def subscriptions_for_dataset(%DB.Dataset{id: dataset_id}) do
    base_query()
    |> preload([:contact])
    |> where([notification_subscription: ns], ns.dataset_id == ^dataset_id)
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
  def reason_to_str(reason) when is_binary(reason), do: reason |> String.to_existing_atom() |> reason_to_str()

  def reason_to_str(reason) when is_atom(reason) do
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
        resources_changed: dgettext("notification_subscription", "resources_changed")
      },
      reason
    )
  end
end
