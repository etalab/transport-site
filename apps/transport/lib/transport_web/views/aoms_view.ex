defmodule TransportWeb.AOMSView do
  use TransportWeb, :view
  import Helpers

  def format_bool(bool), do: if bool, do: "✅", else: "❌"
  def format_count(count), do: if count == 0, do: "❌", else: "✅ (#{count})"
end
