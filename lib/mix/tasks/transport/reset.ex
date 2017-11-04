defmodule Mix.Tasks.Transport.Reset do
  @moduledoc """
  Deletes stuff from the database.
  """

  use Mix.Task

  def run(_) do
    Mix.Task.run "app.start", []
    Mongo.delete_many(:mongo, "datasets", %{}, pool: DBConnection.Poolboy)
  end
end
