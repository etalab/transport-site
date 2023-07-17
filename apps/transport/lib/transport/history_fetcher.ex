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
    preload_validations = Keyword.get(options, :preload_validations, true)
    max_records = Keyword.get(options, :max_records)

    impl().history_resources(dataset,
      preload_validations: preload_validations,
      max_records: max_records
    )
  end
end

defmodule Transport.History.Fetcher.Database do
  @moduledoc """
  Fetch %DB.ResourceHistory models from the database
  for a %DB.Dataset
  """
  @behaviour Transport.History.Fetcher
  import Ecto.Query
  alias DB.{Dataset, Repo}

  @impl true
  def history_resources(%Dataset{id: dataset_id}, options \\ []) do
    # NOTE: default values are provided by the wrapper
    preload_validations = Keyword.get(options, :preload_validations)
    max_records = Keyword.get(options, :max_records)

    latest_resource_history_validation =
      DB.MultiValidation
      |> distinct([mv], mv.resource_history_id)
      |> order_by([mv], asc: mv.resource_history_id, desc: mv.inserted_at)
      |> preload(:metadata)

    dataset_id_sub =
      DB.ResourceHistory.base_query()
      |> where([resource_history: rh], fragment("(?->>'dataset_id')::bigint = ?", rh.payload, ^dataset_id))
      |> select([resource_history: rh], rh.id)

    result =
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

    result =
      if preload_validations do
        result
        |> preload([], validations: ^latest_resource_history_validation)
      else
        result
      end

    result
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
  def history_resources(%DB.Dataset{}, _options \\ []), do: []
end
