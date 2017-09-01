defmodule Mix.Tasks.Npm do
  @moduledoc """
  Executes npm scripts from assets directory.
  """

  use Mix.Task

  def run([cmd | _tail]) do
    case Mix.shell.cmd("cd ./assets && npm #{cmd}", stderr_to_stdout: true) do
      0 -> :ok
      a -> raise "npm command failure exit code: #{a}"
    end
  end
end
