defmodule DB.ResourceUnavailability do
  @moduledoc """
  Model used to store when a resource is not available over HTTP
  (timeout, server errors etc)
  """
  alias DB.{Repo, Resource}

  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  typed_schema "resource_unavailability" do
    field(:start, :utc_datetime)
    field(:end, :utc_datetime)
    timestamps(type: :utc_datetime_usec)

    belongs_to(:resource, Resource)
  end

  @spec ongoing_unavailability(Resource.t()) :: nil | __MODULE__.t()
  def ongoing_unavailability(%Resource{id: resource_id}) do
    __MODULE__
    |> where([r], r.resource_id == ^resource_id and is_nil(r.end))
    |> order_by([r], desc: r.start)
    |> limit(1)
    |> Repo.one()
  end
end
