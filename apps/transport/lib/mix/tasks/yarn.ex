defmodule Mix.Tasks.Yarn do
  @moduledoc """
  Executes yarn scripts from assets directory.
  """

  use Mix.Task

  def run([cmd | _tail]) do
    case Mix.shell.cmd("cd apps/transport/client && yarn #{cmd}", stderr_to_stdout: true) do
      0 -> :ok
      a -> raise "yarn command failure exit code: #{a}"
    end
  end
end
