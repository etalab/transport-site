defmodule Mix.Tasks.Elm do
  @moduledoc """
  Executes elm scripts from assets directory.
  """

  use Mix.Task

  def run([cmd | _tail]) do
    case Mix.shell.cmd("cd ./client && npm run elm-#{cmd}", stderr_to_stdout: true) do
      0 -> :ok
      a -> raise "elm-#{cmd} command failure exit code: #{a}"
    end
  end
end
