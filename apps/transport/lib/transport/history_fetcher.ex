defmodule Transport.History.Fetcher do
  @moduledoc """
  Boundary for all retrieval resources' history, with an indirection to
  the default implementation. This allows easy stubbing of history system
  for tests which have no interest in it (that is: most of the tests).
  """
  @callback history_resources(DB.Dataset.t()) :: [map()]
  @callback history_resources(DB.Dataset.t(), keyword()) :: [map()]

  def impl, do: Application.get_env(:transport, :history_impl)

  def history_resources(%DB.Dataset{} = dataset, options \\ []) do
    options = Keyword.validate!(options, max_records: nil, preload_validations: true, fetch_mode: :all)
    impl().history_resources(dataset, options)
  end
end

defmodule Transport.History.Fetcher.Database do
  @moduledoc """
  Fetch %DB.ResourceHistory models from the database
  for a %DB.Dataset
  """
  @behaviour Transport.History.Fetcher
  import Ecto.Query

  @impl true
  def history_resources(%DB.Dataset{id: dataset_id}, options \\ []) do
    # NOTE: default values are provided by the wrapper
    preload_validations = Keyword.fetch!(options, :preload_validations)
    max_records = Keyword.fetch!(options, :max_records)
    fetch_mode = Keyword.fetch!(options, :fetch_mode)

    latest_resource_history_validation =
      DB.MultiValidation.base_query()
      |> distinct([mv], mv.resource_history_id)
      |> order_by([mv], asc: mv.resource_history_id, desc: mv.inserted_at)
      |> DB.ResourceMetadata.join_validation_with_metadata()
      |> select([metadata: m], %{metadata: m})

    dataset_id_sub =
      DB.ResourceHistory.base_query()
      |> where([resource_history: rh], fragment("(?->>'dataset_id')::bigint = ?", rh.payload, ^dataset_id))
      |> select([resource_history: rh], rh.id)

    query =
      DB.ResourceHistory.base_query()
      |> join(:left, [resource_history: rh], r in DB.Resource,
        on: r.id == rh.resource_id and r.dataset_id == ^dataset_id,
        as: :resource
      )
      |> where(
        [resource: r, resource_history: rh],
        not is_nil(r.id) or rh.id in subquery(dataset_id_sub)
      )
      |> order_by([resource_history: rh], desc: rh.inserted_at)

    query =
      if preload_validations do
        query |> preload([], validations: ^latest_resource_history_validation)
      else
        query
      end
      |> maybe_limit(max_records)

    case fetch_mode do
      :all -> DB.Repo.all(query)
      :stream -> DB.Repo.stream(query)
    end
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
  def history_resources(%DB.Dataset{}, _options \\ []), do: []
end
