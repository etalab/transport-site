defmodule TransportWeb.ErrorViewTest do
  use TransportWeb.ConnCase, async: true
  alias TransportWeb.ErrorView

  # Bring render/3 and render_to_string/3 for testing custom views
  import Phoenix.View

  test "render 500.html" do
    assert render_to_string(ErrorView, "500.html", []) =~ "End of the road!"
  end
end
