defmodule Transport.BreakingNews do
  use Agent

  def start_link(_params) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def get_breaking_news do
    Agent.get(__MODULE__, & &1)
  end

  def set_breaking_news(%{msg: ""}) do
    Agent.cast(__MODULE__, fn _ -> %{} end)
  end
  def set_breaking_news(%{level: level, msg: msg}) do
    Agent.cast(__MODULE__, fn _ -> %{level: level, msg: msg} end)
  end
end
