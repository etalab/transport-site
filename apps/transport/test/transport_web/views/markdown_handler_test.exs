defmodule TransportWeb.MarkdownHandlerTest do
  use ExUnit.Case
  alias TransportWeb.MarkdownHandler

  test "the sanitization of a markdown" do
    content = "# Bonjour\n<script>alert(\"xxx\")</script>"
    assert content |> MarkdownHandler.markdown_to_safe_html!() == {:safe, "<h1>\nBonjour</h1>\n\n  alert(\"xxx\")\n"}
  end

  test "renders tables" do
    content = """
    State | Abbrev
    ------|-------
    Texas | TX
    """

    assert content |> MarkdownHandler.markdown_to_safe_html!() == {
             :safe,
             ~s(<table class="table">\n  <thead>\n    <tr>\n      <th>\nState      </th>\n      <th>\nAbbrev      </th>\n    </tr>\n  </thead>\n  <tbody>\n    <tr>\n      <td>\nTexas      </td>\n      <td>\nTX      </td>\n    </tr>\n  </tbody>\n</table>\n)
           }
  end
end
