defmodule Transport.Platform do
  # NOTE: duplicate from `mix.exs`, a bit complicated to DRY apparently
  def apple_silicon? do
    :system_architecture
    |> :erlang.system_info()
    |> List.to_string()
    |> String.starts_with?("aarch64-apple-darwin")
  end
end
