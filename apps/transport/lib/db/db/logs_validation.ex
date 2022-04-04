defmodule DB.LogsValidation do
  @moduledoc """
  LogsValidation schema
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.Resource

  typed_schema "logs_validation" do
    belongs_to(:resource, Resource)
    field(:timestamp, :utc_datetime)
    field(:is_success, :boolean)
    field(:error_msg, :string)
    field(:skipped, :boolean, default: false)
    field(:skipped_reason, :string)
  end
end
