defmodule TransportWeb.PageView do
  use TransportWeb, :view
  import Phoenix.Controller, only: [current_path: 1]
  import TransportWeb.ResourceView, only: [dataset_creation: 0]
  import TransportWeb.BreadCrumbs, only: [breadcrumbs: 1]
  import TransportWeb.DatasetView, only: [upcoming_icon_type_path: 1]

  def current_tiles(tiles), do: Enum.filter(tiles, &(&1.count > 0))

  def upcoming_tiles(tiles) do
    Enum.filter(tiles, &(&1.count == 0 and is_binary(&1.type)))
  end

  def class("y"), do: "good"
  def class(_), do: "bad"

  def thumb("y"), do: "👍"
  def thumb(_), do: "👎"

  def make_link(""), do: "—"
  def make_link(o), do: link("Lien", to: o)
end
