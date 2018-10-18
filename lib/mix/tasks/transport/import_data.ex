defmodule Mix.Tasks.Transport.ImportData do
  @moduledoc """
  Parses and imports datasets from a udata website to the database.
  """

  use Mix.Task
  alias Transport.ReusableData

  def run(_) do
    Mix.Task.run("app.start", [])

    ReusableData.import()
  end
end
