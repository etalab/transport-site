defmodule DB.Notification do
  @moduledoc """
  A list of emails notifications sent, with email addresses encrypted
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset
  import Ecto.Query
  import Transport.NotificationReason

  typed_schema "notifications" do
    field(:reason, Ecto.Enum, values: all_reasons())

    belongs_to(:dataset, DB.Dataset)
    belongs_to(:contact, DB.Contact)
    belongs_to(:notification_subscription, DB.NotificationSubscription)
    # `dataset_datagouv_id` may be useful if the linked dataset gets deleted
    field(:dataset_datagouv_id, :string)
    field(:email, DB.Encrypted.Binary)
    # Should be used to search rows matching an email address
    # https://hexdocs.pm/cloak_ecto/install.html#usage
    field(:email_hash, Cloak.Ecto.SHA256)
    # Possible roles come from Transport.NotificationReason
    field(:role, Ecto.Enum, values: possible_roles())
    field(:payload, :map)

    timestamps(type: :utc_datetime_usec)
  end

  def base_query, do: from(n in __MODULE__, as: :notification)

  # This `insert!/1` clause should be used when saving notifications
  # without a subscriptions.
  # This is used for unavoidable notifications: warning about inactivity,
  # periodic reminder, promoting user spaces etc.
  def insert!(args) when is_map(args), do: %__MODULE__{} |> changeset(args) |> DB.Repo.insert!()

  def insert!(
        %DB.NotificationSubscription{
          id: ns_id,
          role: role,
          reason: reason,
          contact: %DB.Contact{id: contact_id, email: email}
        },
        %{} = payload
      ) do
    insert!(%{
      notification_subscription_id: ns_id,
      role: role,
      reason: reason,
      contact_id: contact_id,
      email: email,
      payload: payload
    })
  end

  def insert!(
        %DB.Dataset{id: dataset_id, datagouv_id: datagouv_id},
        %DB.NotificationSubscription{
          id: ns_id,
          role: role,
          reason: reason,
          contact: %DB.Contact{id: contact_id, email: email}
        },
        # `payload` should always include a `job_id` to find other
        # `DB.Notification` rows that have been sent in the same batch.
        %{job_id: _} = payload
      ) do
    insert!(%{
      role: role,
      reason: reason,
      dataset_id: dataset_id,
      dataset_datagouv_id: datagouv_id,
      contact_id: contact_id,
      email: email,
      notification_subscription_id: ns_id,
      payload: payload
    })
  end

  @doc """
  Gets a list of notifications' reasons and times sent related to a specific dataset over a given number of days.
  """
  @spec recent_reasons(DB.Dataset.t(), pos_integer()) :: [%{reason: atom, timestamp: DateTime.t()}]
  def recent_reasons(%DB.Dataset{id: dataset_id}, nb_days) when is_integer(nb_days) and nb_days > 0 do
    datetime_limit = DateTime.add(DateTime.utc_now(), -nb_days, :day)

    enabled_reasons = [
      reason(:dataset_with_error),
      reason(:expiration),
      reason(:resource_unavailable)
    ]

    base_query()
    |> where([notification: n], not is_nil(n.payload))
    |> where([notification: n], n.reason in ^enabled_reasons and n.role == :producer)
    |> where([notification: n], n.inserted_at >= ^datetime_limit and n.dataset_id == ^dataset_id)
    |> group_by([notification: n], [fragment("?->'job_id'", n.payload), n.reason, n.payload])
    |> order_by([notification: n], desc: min(n.inserted_at))
    |> select([notification: n], %{
      reason: n.reason,
      timestamp: min(n.inserted_at),
      payload: first_value(n.payload) |> over(partition_by: fragment("?->'job_id'", n.payload))
    })
    |> DB.Repo.all()
  end

  def changeset(struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [
      :reason,
      :dataset_id,
      :dataset_datagouv_id,
      :contact_id,
      :notification_subscription_id,
      :email,
      :role,
      :payload
    ])
    |> validate_required([:reason, :email, :role])
    |> validate_format(:email, ~r/@/)
    |> put_hashed_fields()
    |> DB.NotificationSubscription.validate_reason_by_role()
    |> DB.NotificationSubscription.validate_reason_by_scope()
  end

  defp put_hashed_fields(%Ecto.Changeset{} = changeset) do
    changeset |> put_change(:email_hash, get_field(changeset, :email))
  end
end
