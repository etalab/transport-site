defmodule DB.ResourceHistory do
  @moduledoc """
  ResourceHistory stores metadata when resources are historicized.
  """
  use Ecto.Schema
  use TypedEctoSchema

  @derive {Jason.Encoder, only: [:datagouv_id, :payload, :last_up_to_date_at, :inserted_at, :updated_at]}
  typed_schema "resource_history" do
    field(:datagouv_id, :string)
    field(:payload, :map)
    # the last moment we checked and the resource history was corresponding to the real online resource
    field(:last_up_to_date_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
    # the moment the resource history was created. Can be different from the automatic timestamps in case
    # we retroactively populate the table for example.
    field(:created_at, :utc_datetime_usec)
  end
end
