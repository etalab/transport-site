defmodule Mix.Tasks.Transport.ResetAndImportData do
  @moduledoc """
  Resets the dataset database, seeds it and import them.

  This is an alias to avoid running the three tasks one by one.
  """

  use Mix.Task

  def run(_) do
    Mix.Task.run("transport.reset", [])
    Mix.Task.run("transport.seed", [])
    Mix.Task.run("transport.import_data", [])
  end
end
