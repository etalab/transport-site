defmodule Mix.Tasks.Transport.SimpleValidation do
  @moduledoc """
  Passes a dataset’s url to the validator and stores the validation results in the database
  """

  use Mix.Task
  alias Transport.{Dataset, Repo}

  def run(_) do
    Mix.Task.run("app.start", [])

    Dataset
    |> Repo.all()
    |> Enum.filter(&Dataset.needs_validation/1)
    |> Enum.each(&Dataset.validate_and_save/1)
  end
end
