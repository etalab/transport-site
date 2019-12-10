defmodule TransportWeb.AOMSView do
  use TransportWeb, :view

  def format_bool(bool), do: if bool, do: "✅", else: "❌"
end
