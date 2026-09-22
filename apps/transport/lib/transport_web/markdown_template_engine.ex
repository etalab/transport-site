defmodule TransportWeb.MarkdownTemplateEngine do
  @moduledoc """
  Template engine for `.md` templates, replacing `PhoenixMarkdown.Engine` which relied on
  the retired Earmark library.

  Markdown is rendered at compile time, then the result is compiled by EEx. Since the Markdown
  renderer would escape or URL-encode EEx tags, they are swapped for inert placeholders before
  rendering and put back afterwards.
  """
  @behaviour Phoenix.Template.Engine

  # Mirrors the Earmark defaults PhoenixMarkdown was relying on: smart punctuation,
  # bare URLs turned into links, GFM strikethrough and raw HTML left untouched.
  @options [
    extension: [autolink: true, strikethrough: true],
    parse: [smart: true],
    render: [unsafe: true]
  ]

  @eex_tag ~r/<%.*?%>/s

  @impl Phoenix.Template.Engine
  def compile(path, _name) do
    {markdown, eex_tags} = path |> File.read!() |> extract_eex_tags()

    markdown
    |> MDEx.to_html!(@options)
    |> restore_eex_tags(eex_tags)
    |> EEx.compile_string(engine: Phoenix.HTML.Engine, file: path, line: 1)
  end

  defp extract_eex_tags(markdown) do
    {chunks, tags} =
      @eex_tag
      |> Regex.split(markdown, include_captures: true)
      |> Enum.map_reduce([], fn chunk, tags ->
        if Regex.match?(@eex_tag, chunk) do
          {placeholder(length(tags)), [chunk | tags]}
        else
          {chunk, tags}
        end
      end)

    {Enum.join(chunks), Enum.reverse(tags)}
  end

  defp restore_eex_tags(html, tags) do
    tags
    |> Enum.with_index()
    |> Enum.reduce(html, fn {tag, index}, html -> String.replace(html, placeholder(index), tag) end)
  end

  # Only letters and digits, so that neither the Markdown renderer nor URL encoding alters it.
  defp placeholder(index), do: "eexTagPlaceholder#{index}x"
end
