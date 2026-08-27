defmodule TransportWeb.Components.ColorfulButton do
  @moduledoc """
  Colorful button that acts as a link packaged as a Phoenix Component.

  Useful for navigation.
  """

  use Phoenix.Component

  attr(:variant, :atom, default: :valid)
  attr(:striped, :boolean, default: false)
  attr(:selected, :boolean, default: false)
  attr(:href, :string, required: true)

  slot(:icon)
  slot(:label, required: true)

  def colorful_link(assigns) do
    ~H"""
    <.link class={classnames(@variant, @striped, @selected)} href={@href}>
      {render_slot(@icon)}
      <span>
        {render_slot(@label)}
      </span>
    </.link>
    """
  end

  def classnames(variant, striped, selected) do
    variant_class =
      case variant do
        :valid -> ["variant-valid"]
        :error -> ["variant-error"]
        :warning -> ["variant-warning"]
        :information -> ["variant-information"]
        _ -> ["variant-valid"]
      end

    striped_class =
      if striped do
        ["striped"]
      else
        []
      end

    selected_class =
      if selected do
        ["selected"]
      else
        []
      end

    Enum.join(["colorful"] ++ variant_class ++ striped_class ++ selected_class, " ")
  end
end
