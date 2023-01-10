defmodule DB.DataImportBatch do
  @moduledoc """
  Table storing the summary of a data import consolidation.
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "data_import_batch" do
    field(:summary, :map)
    timestamps(type: :utc_datetime_usec)
  end
end
