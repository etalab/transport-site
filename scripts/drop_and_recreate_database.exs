# Useful script if you need to reproduce migrations issues
# such as https://github.com/etalab/transport-site/issues/4358

defmodule Command do
  def mix_root_folder, do: Path.join(__DIR__, "..")
  def run(cmd), do: {_, 0} = System.shell(cmd, cd: mix_root_folder())
end

Command.run("mix ecto.drop")
Command.run("mix ecto.create")
Command.run("mix ecto.migrate")
