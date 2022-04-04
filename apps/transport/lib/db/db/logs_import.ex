defmodule DB.LogsImport do
  @moduledoc """
  LogsImport schema
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.Dataset

  typed_schema "logs_import" do
    field(:datagouv_id, :string)
    field(:timestamp, :utc_datetime)
    field(:is_success, :boolean)
    field(:error_msg, :string)
    belongs_to(:dataset, Dataset)
  end
end
