defmodule DB.DataImport do
  @moduledoc """
  Table linking a ResourceHistory with a DataImport
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "data_import" do
    belongs_to(:resource_history, DB.ResourceHistory)
  end
end
