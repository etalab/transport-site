defmodule TransportWeb.MarkdownHandlerTest do
  use ExUnit.Case
  alias TransportWeb.MarkdownHandler

  test "the sanitization of a markdown" do
    content = "# Bonjour\n<script>alert(\"xxx\")</script>"
    assert content |> MarkdownHandler.markdown_to_safe_html!() == {:safe, "<h1>\nBonjour</h1>\n\n  alert(\"xxx\")\n"}
  end

  test "a markdown keeps linebreaks" do
    content_with_r = "Bonjour,\r\n\r\nLes données seront périmées à la fin du mois d'Août."
    content_with_only_n = "Bonjour  \nmerci de votre vigilance."

    assert content_with_r |> MarkdownHandler.markdown_to_safe_html!() ==
             {:safe, "<p>\nBonjour,</p>\n<p>\nLes données seront périmées à la fin du mois d’Août.</p>\n"}

    assert content_with_only_n |> MarkdownHandler.markdown_to_safe_html!() ==
             {:safe, "<p>\nBonjour  <br />\nmerci de votre vigilance.</p>\n"}
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
