defmodule TransportWeb.DatasetViewTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import TransportWeb.DatasetView

  doctest TransportWeb.DatasetView

  test "the html content of a markdown description" do
    content = "# coucou"
    dataset = %DB.Dataset{description: content}
    assert description(dataset) == {:safe, "<h1>\ncoucou</h1>\n"}
  end

  test "if the html produced is sanitized" do
    content = "<p \" onmouseout=\"alert('Gotcha!')\">coucou</p>"
    dataset = %DB.Dataset{description: content}
    assert description(dataset) == {:safe, "<p>\ncoucou</p>\n"}
  end
end
