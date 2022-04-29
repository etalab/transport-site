defmodule DB.MultiValidation do
  @moduledoc """
  Validation model allowing multiple validations on the same data
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "multi_validations" do
    field(:validation_timestamp, :utc_datetime_usec)
    field(:validator, :string)
    field(:transport_tools_version, :string)
    field(:command, :string)
    field(:result, :map)
    field(:data_vis, :map)
    field(:metadata, :map)

    belongs_to(:resource, DB.Resource)
    belongs_to(:resource_history, DB.ResourceHistory)
    field(:validated_data_name, :string)

    belongs_to(:secondary_resource, DB.Resource, foreign_key: :secondary_resource_id)
    belongs_to(:secondary_resource_history, DB.ResourceHistory, foreign_key: :secondary_resource_history_id)
    field(:secondary_validated_data_name, :string)

    timestamps(type: :utc_datetime_usec)
  end
end
