defmodule TransportWeb.PageView do
  use TransportWeb, :view

  def class("y"), do: "good"
  def class(_), do: "bad"

  def thumb("y"), do: "👍"
  def thumb(_), do: "👎"
end
