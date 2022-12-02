defmodule DB.DatasetHistoryResources do
  @moduledoc """
  Resources that are part of a dataset history
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.{Dataset, LogsValidation, Repo, ResourceUnavailability, Validation}

  typed_schema "dataset_history_resources" do
    belongs_to(:dataset_history, DB.DatasetHistory)
    belongs_to(:resource, DB.Resource)
    belongs_to(:resource_history, DB.ResourceHistory)
    belongs_to(:resource_metadata, DB.ResourceMetadata)
    field(:payload, :map)
  end
end
