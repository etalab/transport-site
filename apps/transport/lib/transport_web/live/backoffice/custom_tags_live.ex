defmodule TransportWeb.CustomTagsLive do
  use Phoenix.LiveView

  def render(assigns) do
    ~H"""
    coucou les tags
    """
  end

  def mount(
        _params,
        _session,
        socket
      ) do
    {:ok, socket}
  end
end
