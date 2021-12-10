defmodule DB.ResourceUnavailability do
  @moduledoc """
  Model used to store when a resource is not available over HTTP
  (timeout, server errors etc)
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "resource_unavailability" do
    field(:start, :utc_datetime)
    field(:end, :utc_datetime)
    timestamps(type: :utc_datetime_usec)

    has_many(:resources, Resource)
  end
end
