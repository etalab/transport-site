defmodule Mix.Tasks.Transport.SimpleValidation do
  @moduledoc """
  Passes a dataset’s url to the validator and stores the validation results in the database
  """

  use Mix.Task
  alias DB.Resource

  def run(args) do
    Mix.Task.run("app.start", [])

    Resource.validate_and_save_all(args)
  end
end
