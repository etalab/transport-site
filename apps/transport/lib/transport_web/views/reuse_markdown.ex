defmodule TransportWeb.ReuseMarkdown do
  @moduledoc """
  Markdown helpers for reuse descriptions rendered inside dataset pages.

  Reuse cards use `<h3>` for their title, so any headings in the markdown
  description must be shifted up to avoid breaking the page heading hierarchy:

  - h1 → h4
  - h2 → h5
  - h3/h4/h5/h6 → h6 (already too deep)
  """

  @doc """
  Shift heading levels in an HTML fragment.

  ## Examples

      iex> shift_headings("<h1>Title</h1>")
      "<h4>Title</h4>"

      iex> shift_headings("<h2>Sub</h2><p>Text</p>")
      "<h5>Sub</h5><p>Text</p>"

      iex> shift_headings("<h6>Deep</h6>")
      "<h6>Deep</h6>"
  """
  @spec shift_headings(String.t()) :: String.t()
  def shift_headings(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.traverse_and_update(&shift_tag/1)
    |> Floki.raw_html()
  end

  defp shift_tag({"h" <> level, attrs, children}) when level in ["1", "2", "3", "4", "5", "6"] do
    new_level =
      case level do
        "1" -> "4"
        "2" -> "5"
        # h3-h6 all become h6
        _ -> "6"
      end

    {"h" <> new_level, attrs, children}
  end

  defp shift_tag(node), do: node
end
