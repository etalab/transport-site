defmodule TransportWeb.ReuseMarkdownTest do
  use ExUnit.Case
  alias TransportWeb.ReuseMarkdown

  describe "shift_headings/1" do
    test "shifts h1 to h4" do
      assert ReuseMarkdown.shift_headings("<h1>Titre</h1>") == "<h4>Titre</h4>"
    end

    test "shifts h2 to h5" do
      assert ReuseMarkdown.shift_headings("<h2>Sous-titre</h2>") == "<h5>Sous-titre</h5>"
    end

    test "shifts h3 through h6 to h6" do
      assert ReuseMarkdown.shift_headings("<h3>Section</h3>") == "<h6>Section</h6>"
      assert ReuseMarkdown.shift_headings("<h4>Subsection</h4>") == "<h6>Subsection</h6>"
      assert ReuseMarkdown.shift_headings("<h5>Nested</h5>") == "<h6>Nested</h6>"
      assert ReuseMarkdown.shift_headings("<h6>Deep</h6>") == "<h6>Deep</h6>"
    end

    test "leaves non-heading tags untouched" do
      input = "<p>Hello</p><strong>Bold</strong>"
      assert ReuseMarkdown.shift_headings(input) == input
    end

    test "shifts headings inside nested HTML" do
      input = "<div><h1>Section</h1><p>Text</p><h2>Sub</h2></div>"
      result = ReuseMarkdown.shift_headings(input)
      assert result =~ ~r/<h4>(?s).*Section<\/h4>/
      assert result =~ ~r/<h5>(?s).*Sub<\/h5>/
    end

    test "preserves attributes on shifted headings" do
      input = ~s(<h1 class="title">Title</h1>)
      assert ReuseMarkdown.shift_headings(input) =~ ~r/<h4\s+class="title">/i
    end

    test "handles mixed content with paragraphs and lists" do
      input = "<h1>Intro</h1><p>Some text</p><ul><li>Bullet</li></ul>"
      result = ReuseMarkdown.shift_headings(input)
      assert result =~ ~r/<h4>Intro<\/h4>/
      assert result =~ ~r/<p>Some text<\/p>/
      assert result =~ ~r/<ul>/
    end

    test "handles multiple headings of different levels" do
      input = "<h1>A</h1><h2>B</h2><h3>C</h3>"
      result = ReuseMarkdown.shift_headings(input)
      assert result =~ ~r/<h4>A<\/h4>/
      assert result =~ ~r/<h5>B<\/h5>/
      assert result =~ ~r/<h6>C<\/h6>/
    end
  end
end
