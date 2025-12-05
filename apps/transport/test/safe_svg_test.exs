defmodule SafeSVGTest do
  @moduledoc """
  Check that SVG don't embed JavaScript
  """
  use ExUnit.Case, async: true

  @false_positives ["apps/transport/client/node_modules/template.data.gouv.fr/dist/images/logo-marianne-brassard.svg"]

  test "SVGs don't have a script tag" do
    files =
      "../../apps/transport/**/*.svg"
      |> Path.wildcard()
      |> Enum.reject(&(&1 in @false_positives))
      |> Enum.filter(&potential_issue_detected?/1)
      |> Enum.map(&Path.relative_to(&1, "../.."))

    assert files == []
  end

  def potential_issue_detected?(file) do
    file
    |> File.read!()
    |> String.contains?("<script")
  end
end
