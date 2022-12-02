defmodule DB.DatasetHistory do
  @moduledoc """
  Historisation of data related to a dataset.
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.{Dataset, LogsValidation, Repo, ResourceUnavailability, Validation}

  typed_schema "dataset_history" do
    belongs_to(:dataset, Dataset)
    field(:dataset_datagouv_id, :binary)
    field(:timestamp, :utc_datetime_usec)
    field(:payload, :map)
    has_many(:dataset_history_resources, DB.DatasetHistoryResources)
  end
end
