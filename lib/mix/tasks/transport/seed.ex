defmodule Mix.Tasks.Transport.Seed do
  @moduledoc """
  Seeds stuff to the database.
  """

  use Mix.Task

  def run(_) do
    Mix.Task.run("app.start", [])
    Mongo.insert_many(:mongo, "datasets", datasets(), pool: DBConnection.Poolboy)
  end

  defp datasets do
    "priv/repo/datasets.json"
    |> File.read!
    |> Poison.decode!
  end
end
