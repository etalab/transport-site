alias Transport.ReusableData
defmodule Mix.Tasks.Transport.SimpleValidation do
  @moduledoc """
  Passes a dataset’s url to the validator and stores the validation results in the database
  """

  use Mix.Task

  def run(_) do
    Mix.Task.run("app.start", [])
    ReusableData.list_datasets
    |> Enum.each(&ReusableData.validate_and_save/1)
  end
end
