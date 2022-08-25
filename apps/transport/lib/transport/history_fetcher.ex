defmodule Transport.History.Fetcher do
  @moduledoc """
  Boundary for all retrieval resources' history, with an indirection to
  the default implementation. This allows easy stubbing of history system
  for tests which have no interest in it (that is: most of the tests).
  """
  @callback history_resources(DB.Dataset.t()) :: [map()]
  @callback history_resources(DB.Dataset.t(), integer() | nil) :: [map()]

  def impl, do: Application.get_env(:transport, :history_impl)

  def history_resources(%DB.Dataset{} = dataset, max_records \\ nil), do: impl().history_resources(dataset, max_records)
end

defmodule Transport.History.Fetcher.Database do
  @moduledoc """
  Fetch %DB.ResourceHistory models from the database
  for a %DB.Dataset
  """
  @behaviour Transport.History.Fetcher
  import Ecto.Query
  alias DB.{Dataset, Repo, Resource, ResourceHistory}

  @impl true
  def history_resources(%Dataset{id: dataset_id}, max_records \\ nil)
      when (is_integer(max_records) and max_records > 0) or is_nil(max_records) do
    ResourceHistory
    |> join(:left, [rh], r in Resource, on: rh.resource_id == r.id and r.dataset_id == ^dataset_id)
    |> where([_rh, r], not is_nil(r.id) or fragment("cast(payload->>'dataset_id' as bigint) = ?", ^dataset_id))
    |> order_by([rh, _r], desc: rh.inserted_at)
    |> select([rh, _r], rh)
    |> maybe_limit(max_records)
    |> Repo.all()
  end

  defp maybe_limit(%Ecto.Query{} = query, nil), do: query
  defp maybe_limit(%Ecto.Query{} = query, max_records), do: query |> limit(^max_records)
end

defmodule Transport.History.Fetcher.Null do
  @moduledoc """
  A default implementation returning an empty history,
  useful as a default implementation for dev.
  """
  @behaviour Transport.History.Fetcher

  @impl true
  def history_resources(%DB.Dataset{}, _ \\ nil), do: []
end
