defmodule TransportWeb.ExploreChannel do
  @moduledoc """
  A Phoenix channel used to deliver real-time data to a view.
  """

  use Phoenix.Channel

  @explore_topic "explore"
  @viewers_key "viewers"

  def explore_topic, do: @explore_topic
  def viewers_key, do: @viewers_key

  def join(@explore_topic, _message, socket) do
    send(self(), :after_join)
    {:ok, socket}
  end

  def handle_info(:after_join, socket) do
    {:ok, _} = TransportWeb.Presence.track(socket, @viewers_key, %{})
    {:noreply, socket}
  end
end
