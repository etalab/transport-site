defmodule TransportWeb.PageView do
  use TransportWeb, :view

  def class("y"), do: "good"
  def class(_), do: "bad"

  def thumb("y"), do: "👍"
  def thumb(_), do: "👎"

  def make_link(""), do: "—"
  def make_link(o), do: link("Lien", to: o)
end
