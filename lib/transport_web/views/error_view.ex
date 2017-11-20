defmodule TransportWeb.ErrorView do
  use TransportWeb, :view

  def render("500.html", assigns) do
    render(__MODULE__, "internal_server_error.html", assigns)
  end
end
