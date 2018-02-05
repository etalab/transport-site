defmodule TransportWeb.API.DiscussionView do
  alias TransportWeb.API.JSONView

  def render(conn, assigns) do
    JSONView.render(conn, assigns)
  end
end
