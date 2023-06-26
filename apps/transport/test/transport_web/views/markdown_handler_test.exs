defmodule TransportWeb.MarkdownHandlerTest do
  use ExUnit.Case
  alias TransportWeb.MarkdownHandler

  test "the sanitization of a markdown" do
    content = "# Bonjour\n<script>alert(\"xxx\")</script>"
    assert content |> MarkdownHandler.markdown_to_safe_html!() == {:safe, "<h1>\nBonjour</h1>\n\n  alert(\"xxx\")\n"}
  end

  test "a markdown keeps linebreaks" do
    content_with_r = "Bonjour,\r\n\r\nLes données seront périmées à la fin du mois d'Août."
    content_with_only_n = "Bonjour\nmerci de votre vigilance."

    assert content_with_r |> MarkdownHandler.markdown_to_safe_html!() ==
             {:safe, "<p>\nBonjour,</p>\n<p>\nLes données seront périmées à la fin du mois d’Août.</p>\n"}

    assert content_with_only_n |> MarkdownHandler.markdown_to_safe_html!() ==
             {:safe, "<p>\nBonjour  <br />\nmerci de votre vigilance.</p>\n"}
  end

  test "renders links" do
    content =
      "Bonjour,\r\nLa page précise une licence odc-oDbl et sur le site de vélib on trouve la licence d'etalab https://www.velib-metropole.fr/donnees-open-data-gbfs-du-service-velib-metropole\r\n"

    assert content |> MarkdownHandler.markdown_to_safe_html!() ==
             {:safe,
              "<p>\nBonjour,  <br />\nLa page précise une licence odc-oDbl et sur le site de vélib on trouve la licence d’etalab <a href=\"https://www.velib-metropole.fr/donnees-open-data-gbfs-du-service-velib-metropole\">https://www.velib-metropole.fr/donnees-open-data-gbfs-du-service-velib-metropole</a></p>\n"}
  end

  test "renders code" do
    content =
      "Cela pourrait être une bonne chose de rajouter tout de meme l'url en `license_url` (du fichier `system_information.json`)"

    assert content |> MarkdownHandler.markdown_to_safe_html!() ==
             {:safe,
              "<p>\nCela pourrait être une bonne chose de rajouter tout de meme l’url en <code>license_url</code> (du fichier <code>system_information.json</code>)</p>\n"}
  end

  # This is weird, I keep this as the current behaviour, but do we want this?
  test "does render HTML elements inside Markdown code" do
    content = "<h1>This is a title</h1>"
    assert content |> MarkdownHandler.markdown_to_safe_html!() == {:safe, "<h1>\n  This is a title</h1>\n"}
  end

  test "does escape dangerous HTML tags" do
    content = "<script>alert('Boo!');</script>"
    assert content |> MarkdownHandler.markdown_to_safe_html!() == {:safe, "\n  alert('Boo!');\n"}
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
