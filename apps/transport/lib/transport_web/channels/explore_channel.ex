defmodule TransportWeb.ExploreChannel do
  use Phoenix.Channel

  def join("explore", _message, socket) do
    {:ok, socket}
  end
end
