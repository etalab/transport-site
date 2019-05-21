defmodule TransportWeb.ErrorViewTest do
  use TransportWeb.ConnCase, async: true
  import Phoenix.View, only: [render_to_string: 3]
  alias TransportWeb.ErrorView

  test "render 500.html" do
    assert render_to_string(ErrorView, "500.html", []) =~ "End of the road!"
  end
end
