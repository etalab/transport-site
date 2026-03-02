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
      |> Earmark.as_html!(gfm_tables: true, breaks: true)
      |> HtmlSanitizeEx.basic_html()
      |> HTML.raw()

    {:safe, String.replace(txt, "<table>", ~s(<table class="table">), global: true)}
  end

  def to_html_with_anchors(markdown) do
    {:ok, html, _} = Earmark.as_html(markdown)

    html
    |> Floki.parse_fragment!()
    |> Floki.traverse_and_update(fn
      {tag, attrs, children} when tag in ["h1", "h2", "h3", "h4"] ->
        # Create a slug from the text content
        text_content = Floki.text(children)
        id = slugify(text_content)

        # Add the ID to the header attributes
        new_attrs = [{"id", id} | attrs]

        # Create the clickable link tag
        anchor_link = {"a", [{"href", "##{id}"}, {"class", "anchor"}], ["#"]}

        # Prepend the anchor to the children
        {tag, new_attrs, [anchor_link | [" " | children]]}

      other ->
        other
    end)
    |> Floki.raw_html()
  end

  defp slugify(text) do
    text
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
  end
end
