defmodule DB.DatasetFollower do
  @moduledoc """
  Represents contacts following datasets.
  We insert data **only for existing contacts and datasets.**
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset
  import Ecto.Query

  typed_schema "dataset_followers" do
    belongs_to(:dataset, DB.Dataset)
    belongs_to(:contact, DB.Contact)
    field(:source, Ecto.Enum, values: [:datagouv, :follow_button, :improved_data_pilot])
    timestamps(type: :utc_datetime_usec)
  end

  def base_query, do: from(df in __MODULE__, as: :dataset_follower)

  def changeset(%__MODULE__{} = struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [:dataset_id, :contact_id, :source])
    |> validate_required([:dataset_id, :contact_id, :source])
    |> assoc_constraint(:dataset)
    |> assoc_constraint(:contact)
    |> unique_constraint([:dataset_id, :contact_id])
  end

  @spec follows_dataset?(DB.Contact.t() | nil, DB.Dataset.t()) :: boolean()
  def follows_dataset?(nil, %DB.Dataset{}), do: false

  def follows_dataset?(%DB.Contact{id: contact_id}, %DB.Dataset{id: dataset_id}) do
    DB.Contact.base_query()
    |> join(:inner, [contact: c], d in assoc(c, :followed_datasets), as: :dataset)
    |> where([contact: c, dataset: d], c.id == ^contact_id and d.id == ^dataset_id)
    |> DB.Repo.exists?()
  end

  def follow!(%DB.Contact{id: contact_id}, %DB.Dataset{id: dataset_id}, source: source) do
    %__MODULE__{}
    |> changeset(%{
      dataset_id: dataset_id,
      contact_id: contact_id,
      source: source
    })
    |> DB.Repo.insert!()
  end

  def unfollow!(%DB.Contact{id: contact_id}, %DB.Dataset{id: dataset_id}) do
    __MODULE__
    |> where([df], df.dataset_id == ^dataset_id and df.contact_id == ^contact_id)
    |> DB.Repo.one!()
    |> DB.Repo.delete!()
  end
end
