defmodule DB.LogsResourceQuality do
  @moduledoc """
  A module for logging information about all the PAN resources "quality",
  ie availability, freshness, correctness, etc
  """

  use Ecto.Schema
  use TypedEctoSchema
  alias DB.Resource

  typed_schema "logs_resource_quality" do
    field(:log_date, :utc_datetime_usec)
    field(:resource_end_date, :date)
    field(:is_available, :boolean)

    belongs_to(:resource, Resource)
  end
end
