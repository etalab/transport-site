defmodule DB.ResourceHistoryMV do
  @moduledoc """
  Materialized view of resource history with direct belongs_to dataset and latest multi_validation.
  """

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: false}
  typed_schema "resource_history_mv" do
    # All this is copied from DB.ResourceHistory schema
    field(:datagouv_id, :string)
    field(:payload, :map)
    # the last moment we checked and the resource history was corresponding to the real online resource
    field(:last_up_to_date_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
    belongs_to(:resource, DB.Resource)
    belongs_to(:reuser_improved_data, DB.ReuserImprovedData)
    has_many(:geo_data_import, DB.GeoDataImport)
    has_many(:validations, DB.MultiValidation)
    has_many(:metadata, DB.ResourceMetadata)

    # Just adding two belongs_to fields
    belongs_to(:dataset, DB.Dataset)
    belongs_to(multi_validation: DB.MultiValidation)
  end
end
