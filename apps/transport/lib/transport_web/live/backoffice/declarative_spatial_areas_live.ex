defmodule TransportWeb.DeclarativeSpatialAreasLive do
  use Phoenix.LiveComponent
  alias TransportWeb.InputHelpers

  def render(assigns) do
    ~H"""
    <div class="pt-24">
      <div :for={{division, index} <- Enum.with_index(@declarative_spatial_areas)} class="pt-6">
        <span class={["label", "custom-tag"] ++ [color_class(division)]}>
          <%= division.nom %> (<%= division.type %>)
          <span class="delete-tag" phx-click="remove_tag" phx-value-id={division.id} phx-target={@myself}></span>
        </span>
        <%= Phoenix.HTML.Form.hidden_input(@form, "declarative_spatial_area_#{index}", value: division.id) %>
      </div>
    </div>
    """
  end

  def color_class(division) do
    "red"
  end
end
