defmodule DB.DatasetHistory do
  @moduledoc """
  Historisation of data related to a dataset.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  typed_schema "dataset_history" do
    belongs_to(:dataset, DB.Dataset)
    field(:dataset_datagouv_id, :binary)
    field(:payload, :map)
    has_many(:dataset_history_resources, DB.DatasetHistoryResources)

    timestamps(type: :utc_datetime_usec)
  end

  def from_old_dataset_slug(slug) do
    __MODULE__
    |> join(:inner, [dh], d in DB.Dataset, on: d.id == dh.dataset_id and d.is_active and d.slug != ^slug)
    |> where([dh], fragment("?->>'slug'", dh.payload) == ^slug)
    |> DB.Repo.one()
  end
end
