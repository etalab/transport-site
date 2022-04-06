defmodule DB.GeoDataImport do
  @moduledoc """
  Links geo_data data with its source
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "geo_data_import" do
      belongs_to(:resource_history, DB.ResourceHistory)
      field(:publish, :boolean)
      has_many(:geo_data, DB.GeoData)
  end
end
