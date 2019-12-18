defmodule TransportWeb.AOMSView do
  use TransportWeb, :view

  def format_bool(nil), do: ""
  def format_bool(true), do: "✅"
  def format_bool(false), do: "❌"
end
