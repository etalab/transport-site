defmodule Transport.Platform do
  @moduledoc """
  A little heuristic to determine if the code is running on a Mac M1.

  Duplicate from `mix.exs`, a bit complicated to DRY apparently.
  """
  def apple_silicon? do
    :system_architecture
    |> :erlang.system_info()
    |> List.to_string()
    |> String.starts_with?("aarch64-apple-darwin")
  end
end
