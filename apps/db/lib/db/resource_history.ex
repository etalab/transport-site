defmodule DB.ResourceHistory do
  @moduledoc """
  ResourceHistory stores metadata when resources are historicized.
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "resource_history" do
    field(:datagouv_id, :string)
    field(:payload, :map)

    timestamps(type: :utc_datetime_usec)
  end
end
