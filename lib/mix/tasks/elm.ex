defmodule Mix.Tasks.Elm do
  @moduledoc """
  Executes elm scripts from assets directory.
  """

  use Mix.Task

  @elm_path "./node_modules/elm/binwrappers/elm-package"

  def run([cmd | _tail]) do
    case Mix.shell.cmd("cd ./assets && #{@elm_path} #{cmd}", stderr_to_stdout: true) do
      0 -> :ok
      a -> raise "elm command failure exit code: #{a}"
    end
  end
end
