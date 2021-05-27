defmodule Transport.History.Fetcher.Mock do
  @behaviour Transport.History.Fetcher

  @moduledoc """
  A default implementation returning an empty history, useful as a default
  implementation for tests unrelated to history.
  """

  def history_resources(%DB.Dataset{}), do: []
end
