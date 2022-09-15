defmodule NoCSSInlineStyleTest do
  @moduledoc """
  Check that we do not use CSS styles inline
  """
  use ExUnit.Case, async: true

  test "Do not use inline CSS styles, except for emails" do
    files =
      "../../apps/**/*.heex"
      |> Path.wildcard()
      |> Enum.reject(&ignore_filepath?/1)
      |> Enum.filter(&potential_css_inline?/1)
      |> Enum.map(&Path.relative_to(&1, "../.."))

    assert files == []
  end

  def ignore_filepath?(filepath) do
    String.contains?(filepath, ["apps/transport/lib/transport_web/templates/email/"])
  end

  def potential_css_inline?(file) do
    file |> File.read!() |> String.contains?("style=")
  end
end
