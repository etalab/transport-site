defmodule TransportWeb.MarkdownHandler do
  @moduledoc """
  Render Markdown as sanitized HTML, marked safe.

  Two entry points depending on where the Markdown comes from: `markdown_to_safe_html!/1` for
  content written by third parties, `vendored_markdown_to_safe_html!/1` for content we ship.
  """
  require HtmlSanitizeEx
  alias Phoenix.HTML

  @common [extension: [table: true, autolink: true, strikethrough: true], parse: [smart: true]]

  # Producers write things like `<trip>` as plain text in their descriptions: rendering raw HTML
  # would make it disappear.
  @external_options @common ++ [render: [hardbreaks: true, escape: true]]

  # The MobilityData validator rules use HTML tables and links on purpose, and wrap their
  # descriptions at a fixed width.
  @vendored_options @common ++ [render: [unsafe: true]]

  @spec markdown_to_safe_html!(binary() | nil) :: HTML.safe()
  def markdown_to_safe_html!(md), do: markdown_to_safe_html!(md, &Function.identity/1)

  @doc """
  The transform receives sanitized HTML and returns the final HTML string.
  """
  @spec markdown_to_safe_html!(binary() | nil, (String.t() -> String.t())) :: HTML.safe()
  def markdown_to_safe_html!(nil, _transform), do: HTML.raw(nil)
  def markdown_to_safe_html!(md, transform), do: to_safe_html(md, @external_options, transform)

  @doc """
  Renders raw HTML instead of escaping it, the content being ours. Still sanitized.
  """
  @spec vendored_markdown_to_safe_html!(binary() | nil) :: HTML.safe()
  def vendored_markdown_to_safe_html!(nil), do: HTML.raw(nil)
  def vendored_markdown_to_safe_html!(md), do: to_safe_html(md, @vendored_options, &Function.identity/1)

  def to_html_with_anchors(markdown) do
    {:ok, html} = MDEx.to_html(markdown, @external_options)

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

  defp to_safe_html(md, options, transform) do
    {:safe, txt} =
      md
      |> MDEx.to_html!(options)
      |> HtmlSanitizeEx.basic_html()
      |> transform.()
      |> HTML.raw()

    {:safe, String.replace(txt, "<table>", ~s(<table class="table">), global: true)}
  end

  defp slugify(text) do
    text
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
  end
end
