defmodule Mix.Tasks.Transport.ImportData do
  @moduledoc """
  Parses and imports datasets from a udata website to the database.
  """

  use Mix.Task
  alias Transport.ImportDataService

  def run(_) do
    Mix.Task.run("app.start", [])

    :mongo
    |> Mongo.find("datasets", %{}, pool: DBConnection.Poolboy)
    |> Enum.map(&ImportDataService.call/1)
  end
end
