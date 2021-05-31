defmodule TransportWeb.MarkdownHandler do
  @moduledoc """
  A module to handle external markdown, sanitize it and mark it safe
  """
  require HtmlSanitizeEx
  alias Phoenix.HTML

  @spec markdown_to_safe_html!(binary()) :: HTML.safe()
  def markdown_to_safe_html!(md) do
    md
    |> Earmark.as_html!()
    |> HtmlSanitizeEx.basic_html()
    |> HTML.raw()
  end
end
