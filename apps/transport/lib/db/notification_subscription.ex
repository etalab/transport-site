defmodule DB.NotificationSubscription do
  @moduledoc """
  Represents a subscription to a notification type for a `DB.Contact`
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.{Changeset, Query}

  @reasons_related_to_datasets [:expiration, :dataset_with_error, :resource_unavailable]
  @other_reasons [:new_dataset, :dataset_now_licence_ouverte]

  typed_schema "notification_subscription" do
    field(:reason, Ecto.Enum, values: @reasons_related_to_datasets ++ @other_reasons)
    field(:source, Ecto.Enum, values: [:admin, :user])

    belongs_to(:contact, DB.Contact)
    belongs_to(:dataset, DB.Dataset)

    timestamps(type: :utc_datetime_usec)
  end

  def base_query, do: from(ns in __MODULE__, as: :notification_subscription)

  def insert!(%{} = fields), do: %__MODULE__{} |> changeset(fields) |> DB.Repo.insert!()

  def changeset(struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [:contact_id, :dataset_id, :reason, :source])
    |> validate_required([:contact_id, :dataset_id, :reason, :source])
    |> assoc_constraint(:contact)
    |> maybe_assoc_constraint_dataset()
    |> unique_constraint([:contact_id, :dataset_id, :reason],
      name: :notification_subscription_contact_id_dataset_id_reason_index
    )
  end

  defp maybe_assoc_constraint_dataset(%Ecto.Changeset{} = changeset) do
    if get_field(changeset, :reason) in reasons_related_to_datasets() do
      changeset |> assoc_constraint(:dataset)
    else
      changeset |> validate_inclusion(:dataset_id, [nil])
    end
  end

  @spec reasons_related_to_datasets :: [atom()]
  def reasons_related_to_datasets, do: @reasons_related_to_datasets
end
