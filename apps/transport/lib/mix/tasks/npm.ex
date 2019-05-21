defmodule Mix.Tasks.Npm do
  @moduledoc """
  Executes npm scripts from assets directory.
  """

  use Mix.Task

  def run([cmd | _tail]) do
    "npm --prefix apps/transport/client #{cmd}"
    |> Mix.shell.cmd(stderr_to_stdout: true)
    |> case do
      0 -> :ok
      a -> raise "npm command failure exit code: #{a}"
    end
  end
end
