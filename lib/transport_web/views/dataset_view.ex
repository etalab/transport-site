defmodule TransportWeb.DatasetView do
  use TransportWeb, :view
  alias Transport.ReusableData
  import Scrivener.HTML

  def render_sidebar_from_type(dataset), do: render_panel_from_type(dataset, "sidebar")
  def render_description_from_type(dataset), do: render_panel_from_type(dataset, "description")

  def render_panel_from_type(dataset, panel_type) do
    render_existing(
      TransportWeb.DatasetView,
      "_#{panel_type}_#{dataset.type}.html",
      dataset: dataset
    )
  end
end
