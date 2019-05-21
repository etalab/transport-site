defmodule TransportWeb.LayoutView do
  use TransportWeb, :view
  alias __MODULE__
  alias Phoenix.Controller

  def current_path(conn) do
    Controller.current_path(conn)
  end
end
