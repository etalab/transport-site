defmodule Transport.Wrapper.HTTPoison do
  @moduledoc """
  Temporary: a HTTPoison wrapper currently used by the history system in
  order to facilitate the use of mocks.

  Ultimately we will create a central HTTP behaviour with all common calls,
  and stop using HTTPoison or Finch directly except in lower level parts.
  """
  def impl, do: Application.get_env(:transport, :httpoison_impl, HTTPoison)
end
