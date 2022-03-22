defmodule TransportWeb.ExploreChannel do
  use Phoenix.Channel

  @moduledoc """
  A Phoenix channel used to deliver real-time data to a view.
  """

  def join("explore", _message, socket) do
    {:ok, socket}
  end
end
