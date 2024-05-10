defmodule Transport.Platform do
  # NOTE: duplicate from `mix.exs`, good enough for now
  def apple_silicon? do
    :system_architecture
    |> :erlang.system_info()
    |> List.to_string()
    |> String.starts_with?("aarch64-apple-darwin")
  end
end
