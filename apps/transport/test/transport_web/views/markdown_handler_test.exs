defmodule TransportWeb.MarkdownHandlerTest do
  use ExUnit.Case
  alias TransportWeb.MarkdownHandler

  test "the sanitization of a markdown" do
    content = "# Bonjour\n<script>alert(\"xxx\")</script>"
    assert content |> MarkdownHandler.markdown_to_safe_html!() == {:safe, "<h1>Bonjour</h1>\nalert(\"xxx\")"}
  end

  test "a markdown keeps linebreaks" do
    content_with_r = "Bonjour,\r\n\r\nLes données seront périmées à la fin du mois d'Août."
    content_with_only_n = "Bonjour\nmerci de votre vigilance."

    assert content_with_r |> MarkdownHandler.markdown_to_safe_html!() ==
             {:safe, "<p>Bonjour,</p>\n<p>Les données seront périmées à la fin du mois d’Août.</p>"}

    assert content_with_only_n |> MarkdownHandler.markdown_to_safe_html!() ==
             {:safe, "<p>Bonjour<br />\nmerci de votre vigilance.</p>"}
  end

  test "renders links" do
    content =
      "Bonjour,\r\nLa page précise une licence odc-oDbl et sur le site de vélib on trouve la licence d'etalab https://www.velib-metropole.fr/donnees-open-data-gbfs-du-service-velib-metropole\r\n"

    assert content |> MarkdownHandler.markdown_to_safe_html!() ==
             {:safe,
              "<p>Bonjour,<br />\nLa page précise une licence odc-oDbl et sur le site de vélib on trouve la licence d’etalab <a href=\"https://www.velib-metropole.fr/donnees-open-data-gbfs-du-service-velib-metropole\">https://www.velib-metropole.fr/donnees-open-data-gbfs-du-service-velib-metropole</a></p>"}
  end

  test "renders code" do
    content =
      "Cela pourrait être une bonne chose de rajouter tout de meme l'url en `license_url` (du fichier `system_information.json`)"

    assert content |> MarkdownHandler.markdown_to_safe_html!() ==
             {:safe,
              "<p>Cela pourrait être une bonne chose de rajouter tout de meme l’url en <code>license_url</code> (du fichier <code>system_information.json</code>)</p>"}
  end

  test "does render HTML elements inside Markdown code" do
    content = "<h1>This is a title</h1>"
    assert content |> MarkdownHandler.markdown_to_safe_html!() == {:safe, "<h1>This is a title</h1>"}
  end

  test "does escape dangerous HTML tags" do
    content = "<script>alert('Boo!');</script>"
    assert content |> MarkdownHandler.markdown_to_safe_html!() == {:safe, "alert('Boo!');"}
  end

  test "renders tables" do
    content = """
    State | Abbrev
    ------|-------
    Texas | TX
    """

    assert content |> MarkdownHandler.markdown_to_safe_html!() == {
             :safe,
             ~s(<table class="table">\n<thead>\n<tr>\n<th>State</th>\n<th>Abbrev</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>Texas</td>\n<td>TX</td>\n</tr>\n</tbody>\n</table>)
           }
  end

  describe "markdown_to_safe_html!/2 with transform" do
    # Shift function matching ReusesLive.shift_headings/1
    defp shift_headings(html) do
      html
      |> Floki.parse_fragment!()
      |> Floki.traverse_and_update(&shift_headings_tag/1)
      |> Floki.raw_html()
    end

    defp shift_headings_tag({tag, attrs, children}) do
      tag =
        case tag do
          "h1" -> "h4"
          unaltered -> unaltered
        end

      {tag, attrs, children}
    end

    test "shifts h1 to h4" do
      content = "# Titre principal"
      {:safe, html} = MarkdownHandler.markdown_to_safe_html!(content, &shift_headings/1)
      assert html =~ ~r/<h4>(?s).*(?:\n)?Titre principal<\/h4>/
    end

    test "sanitizes dangerous HTML" do
      content = "# Titre<svg/onload=alert(1)>\nParagraph"

      {:safe, html} = MarkdownHandler.markdown_to_safe_html!(content, &shift_headings/1)
      refute html =~ ~r/<svg/
      assert html =~ ~r/<h4>/
    end

    test "returns safe empty string for nil input" do
      assert MarkdownHandler.markdown_to_safe_html!(nil, &Function.identity/1) == {:safe, ""}
    end
  end
end
