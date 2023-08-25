defmodule NoHTMLInMarkdownTemplatesTest do
  @moduledoc """
  Check that we do not use `<a href=""></a>` links in Markdown templates
  """
  use ExUnit.Case, async: true

  test "Do not use HTML links in Markdown templates" do
    md_files = "../../apps/transport/lib/transport_web/templates/**/*.html.md" |> Path.wildcard()

    refute Enum.empty?(md_files)
    assert md_files |> Enum.filter(&with_html_link?/1) |> Enum.empty?()
  end

  def with_html_link?(file) do
    file |> File.read!() |> String.contains?("<a href=")
  end
end
