defmodule Transport.LogTimeTaken do
  @moduledoc """
  Provides code to easily measure time taken by an operation
  all while returning the computed value
  """
  defmacro __using__(_opts) do
    quote do
      require Logger
    end
  end

  require Logger

  def log_time_taken(message, cb) do
    {delay, result} = :timer.tc(cb)
    Logger.info("#{message} took #{delay / 1_000_000.0} seconds")
    result
  end
end
