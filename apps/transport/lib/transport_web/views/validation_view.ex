defmodule TransportWeb.ValidationView do
  use TransportWeb, :view
  import Phoenix.Controller, only: [current_url: 1]

  import TransportWeb.ResourceView,
    only: [gtfs_template: 1, netex_template: 0, netex_template: 1, netex_compatibility: 1]

  import TransportWeb.PaginationHelpers

  def render("_" <> _ = partial, assigns) do
    render(TransportWeb.ResourceView, partial, assigns)
  end

  def has_errors?([]), do: false
  def has_errors?(summary) when is_list(summary), do: true
end
