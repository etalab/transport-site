defmodule DB.Notification do
  @moduledoc """
  A list of emails notifications sent, with email addresses encrypted
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "notifications" do
    field(:reason, Ecto.Enum, values: Ecto.Enum.mappings(DB.NotificationSubscription, :reason))

    belongs_to(:dataset, DB.Dataset)
    # `dataset_datagouv_id` may be useful if the linked dataset gets deleted
    field(:dataset_datagouv_id, :string)
    field(:email, DB.Encrypted.Binary)
    # Should be used to search rows matching an email address
    # https://hexdocs.pm/cloak_ecto/install.html#usage
    field(:email_hash, Cloak.Ecto.SHA256)

    timestamps(type: :utc_datetime_usec)
  end

  def base_query, do: from(n in __MODULE__, as: :notification)

  def insert!(reason, email) do
    %__MODULE__{}
    |> changeset(%{reason: reason, email: email})
    |> DB.Repo.insert!()
  end

  def insert!(reason, %DB.Dataset{id: dataset_id, datagouv_id: datagouv_id}, email) do
    %__MODULE__{}
    |> changeset(%{reason: reason, dataset_id: dataset_id, dataset_datagouv_id: datagouv_id, email: email})
    |> DB.Repo.insert!()
  end

  @doc """
  Gets a list of notifications' reasons and times sent related to a specific dataset over a given number of days.
  Notifications are binned according to a 5-minute window.
  """
  @spec recent_reasons_binned(DB.Dataset.t(), pos_integer()) :: [%{reason: atom, timestamp: DateTime.t()}]
  def recent_reasons_binned(%DB.Dataset{id: dataset_id}, nb_days) when is_integer(nb_days) and nb_days > 0 do
    datetime_limit = DateTime.add(DateTime.utc_now(), -nb_days, :day)
    possible_reasons = DB.NotificationSubscription.reasons_related_to_datasets()

    base_query()
    |> where(
      [notification: n],
      n.inserted_at >= ^datetime_limit and n.dataset_id == ^dataset_id and n.reason in ^possible_reasons
    )
    # The function date_bin “bins” the input timestamp into the specified interval (the stride)
    # aligned with a specified origin.
    # https://www.postgresql.org/docs/current/functions-datetime.html#FUNCTIONS-DATETIME-BIN
    |> group_by([notification: n], [n.reason, fragment("date_bin('5 minutes', ?, '2022-01-01')", n.inserted_at)])
    |> order_by([notification: n], desc: fragment("timestamp"))
    |> select([notification: n], %{
      reason: n.reason,
      timestamp: fragment("date_bin('5 minutes', ?, '2022-01-01') at time zone 'utc' as timestamp", n.inserted_at)
    })
    |> DB.Repo.all()
  end

  def changeset(struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [:reason, :dataset_id, :dataset_datagouv_id, :email])
    |> validate_required([:reason, :email])
    |> validate_format(:email, ~r/@/)
    |> put_hashed_fields()
  end

  defp put_hashed_fields(%Ecto.Changeset{} = changeset) do
    changeset |> put_change(:email_hash, get_field(changeset, :email))
  end
end
