defmodule DB.DatasetHistoryResources do
  @moduledoc """
  Resources that are part of a dataset history
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "dataset_history_resources" do
    belongs_to(:dataset_history, DB.DatasetHistory)
    belongs_to(:resource, DB.Resource)
    belongs_to(:resource_history, DB.ResourceHistory)
    field(:resource_history_last_up_to_date_at, :utc_datetime_usec)
    belongs_to(:resource_metadata, DB.ResourceMetadata)
    belongs_to(:validation, DB.MultiValidation)
    field(:payload, :map)
    field(:resource_datagouv_id, :string)
  end
end
