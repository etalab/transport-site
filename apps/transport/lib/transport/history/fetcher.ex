defmodule Transport.History.Fetcher do
  @moduledoc """
  Boundary for all retrieval resources' history, with an indirection to
  the default implementation. This allows easy stubbing of history system
  for tests which have no interest in it (that is: most of the tests).
  """
  @callback history_resources(DB.Dataset.t()) :: [map()]

  def impl, do: Application.get_env(:transport, :history_impl, Fetcher.S3)

  def history_resources(%DB.Dataset{} = dataset), do: impl().history_resources(dataset)
end
