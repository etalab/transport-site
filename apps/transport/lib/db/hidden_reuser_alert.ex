defmodule DB.HiddenReuserAlert do
  @moduledoc """
  Stores alerts hidden by reusers in their reuser space.
  Each entry represents an alert that a user has chosen to hide for 7 days.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.{Changeset, Query}

  @hide_duration_days 7

  @type check_type :: :unavailable_resource | :expiring_resource | :invalid_resource | :recent_discussions

  typed_schema "hidden_reuser_alerts" do
    belongs_to(:contact, DB.Contact)
    belongs_to(:dataset, DB.Dataset)

    field(:check_type, Ecto.Enum,
      values: [:unavailable_resource, :expiring_resource, :invalid_resource, :recent_discussions]
    )

    field(:resource_id, :integer)
    field(:discussion_id, :string)
    field(:hidden_until, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  def base_query, do: from(hra in __MODULE__, as: :hidden_reuser_alert)

  def changeset(struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [:contact_id, :dataset_id, :check_type, :resource_id, :discussion_id, :hidden_until])
    |> validate_required([:contact_id, :dataset_id, :check_type, :hidden_until])
    |> assoc_constraint(:contact)
    |> assoc_constraint(:dataset)
    |> unique_constraint(
      [:contact_id, :dataset_id, :check_type, :resource_id, :discussion_id],
      name: :hidden_reuser_alerts_unique_index
    )
  end

  @doc """
  Hides an alert for a contact for 7 days. Uses upsert to update hidden_until if the alert is already hidden.
  """
  @spec hide!(DB.Contact.t(), DB.Dataset.t(), check_type(), keyword()) :: __MODULE__.t()
  def hide!(%DB.Contact{id: contact_id}, %DB.Dataset{id: dataset_id}, check_type, opts \\ []) do
    resource_id = Keyword.get(opts, :resource_id)
    discussion_id = Keyword.get(opts, :discussion_id)
    hidden_until = DateTime.utc_now() |> DateTime.add(@hide_duration_days, :day)

    %__MODULE__{}
    |> changeset(%{
      contact_id: contact_id,
      dataset_id: dataset_id,
      check_type: check_type,
      resource_id: resource_id,
      discussion_id: discussion_id,
      hidden_until: hidden_until
    })
    |> DB.Repo.insert!(
      on_conflict: {:replace, [:hidden_until, :updated_at]},
      conflict_target: {:unsafe_fragment, "(contact_id, dataset_id, check_type, resource_id, discussion_id)"}
    )
  end

  @doc """
  Returns all active hidden alerts for a contact (where hidden_until > now).
  """
  @spec active_hidden_alerts(DB.Contact.t()) :: [__MODULE__.t()]
  def active_hidden_alerts(%DB.Contact{id: contact_id}) do
    now = DateTime.utc_now()

    base_query()
    |> where([hidden_reuser_alert: hra], hra.contact_id == ^contact_id and hra.hidden_until > ^now)
    |> DB.Repo.all()
  end

  @doc """
  Checks if a specific alert is hidden for a contact.
  """
  @spec hidden?([__MODULE__.t()], integer(), check_type(), keyword()) :: boolean()
  def hidden?(hidden_alerts, dataset_id, check_type, opts \\ []) do
    resource_id = Keyword.get(opts, :resource_id)
    discussion_id = Keyword.get(opts, :discussion_id)

    Enum.any?(hidden_alerts, fn alert ->
      alert.dataset_id == dataset_id and
        alert.check_type == check_type and
        alert.resource_id == resource_id and
        alert.discussion_id == discussion_id
    end)
  end
end
