defmodule TransportWeb.Components.ColorfulButton do
  @moduledoc """
  Colorful button that acts as a link packaged as a Phoenix Component.

  Useful for navigation.
  """

  use Phoenix.Component

  attr(:valid, :boolean, default: true)
  attr(:striped, :boolean, default: false)
  attr(:selected, :boolean, default: false)
  attr(:href, :string, required: true)

  slot(:icon)
  slot(:label, required: true)

  def colorful_link(assigns) do
    ~H"""
    <.link class={classnames(@valid, @striped, @selected)} href={@href}>
      {render_slot(@icon)}
      <span>
        {render_slot(@label)}
      </span>
    </.link>
    """
  end

  defp classnames(valid, striped, selected) do
    validity =
      if valid do
        ["valid"]
      else
        ["invalid"]
      end

    variant =
      if striped do
        ["striped"]
      else
        []
      end

    selected =
      if selected do
        ["selected"]
      else
        []
      end

    Enum.join(["colorful"] ++ validity ++ variant ++ selected, " ")
  end
end
