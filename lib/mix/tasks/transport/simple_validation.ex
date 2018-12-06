defmodule Mix.Tasks.Transport.SimpleValidation do
  @moduledoc """
  Passes a dataset’s url to the validator and stores the validation results in the database
  """

  use Mix.Task
  alias Transport.{Repo, Resource}

  def run(_) do
    Mix.Task.run("app.start", [])

    Resource
    |> Repo.all()
    |> Enum.filter(&Resource.needs_validation/1)
    |> Enum.each(&Resource.validate_and_save/1)
  end
end
