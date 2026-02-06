defmodule DB.IRVEValidFile do
  @moduledoc """
  IRVE file that has been validated and stored. This file refers to a datagouv resource and dataset
  that is not imported on transport.data.gouv, so no reference to the dataset/resource tables.
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "irve_valid_file" do
    field(:datagouv_dataset_id, :string, null: false)
    field(:datagouv_resource_id, :string, null: false)
    field(:checksum, :string, null: false)
    has_many(:irve_valid_pdcs, DB.IRVEValidPDC, foreign_key: :irve_valid_file_id)
    timestamps(type: :utc_datetime_usec)
  end
end
