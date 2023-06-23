defmodule TransportWeb.MarkdownHandler do
  @moduledoc """
  A module to handle external markdown, sanitize it and mark it safe
  """
  require HtmlSanitizeEx
  alias Phoenix.HTML

  @doc """
  transform an external markdown content into safe HTML
  """
  @spec markdown_to_safe_html!(binary() | nil) :: HTML.safe()
  def markdown_to_safe_html!(nil), do: HTML.raw(nil)

  def markdown_to_safe_html!(md) do
    {:safe, txt} =
      md
      |> Earmark.as_html!([gfm_tables: true, breaks: true])
      |> HtmlSanitizeEx.basic_html()
      |> HTML.raw()

    {:safe, String.replace(txt, "<table>", ~s(<table class="table">), global: true)}
  end
end
