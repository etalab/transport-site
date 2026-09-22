defmodule TransportWeb.MarkdownHandler do
  @moduledoc """
  A module to handle external markdown, sanitize it and mark it safe
  """
  require HtmlSanitizeEx
  alias Phoenix.HTML

  # Mirrors what Earmark used to provide: GFM tables, single line breaks, bare URLs turned
  # into links, strikethrough and smart punctuation. Raw HTML is kept and `HtmlSanitizeEx`
  # remains the security boundary.
  @options [
    extension: [table: true, autolink: true, strikethrough: true],
    parse: [smart: true],
    render: [hardbreaks: true, unsafe: true]
  ]

  @doc """
  Transform an external markdown content into safe HTML.
  """
  @spec markdown_to_safe_html!(binary() | nil) :: HTML.safe()
  def markdown_to_safe_html!(nil), do: HTML.raw(nil)

  def markdown_to_safe_html!(md) do
    markdown_to_safe_html!(md, &Function.identity/1)
  end

  @doc """
  Transform markdown to safe HTML with a custom transform applied after the Markdown rendering.
  The transform receives sanitized HTML and returns the final HTML string.
  """
  @spec markdown_to_safe_html!(binary(), (String.t() -> String.t())) :: HTML.safe()
  def markdown_to_safe_html!(nil, _transform), do: HTML.raw(nil)

  def markdown_to_safe_html!(md, transform) do
    {:safe, txt} =
      md
      |> MDEx.to_html!(@options)
      |> HtmlSanitizeEx.basic_html()
      |> transform.()
      |> HTML.raw()

    {:safe, String.replace(txt, "<table>", ~s(<table class="table">), global: true)}
  end

  def to_html_with_anchors(markdown) do
    {:ok, html} = MDEx.to_html(markdown, @options)

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
