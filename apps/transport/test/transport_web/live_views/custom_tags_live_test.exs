defmodule TransportWeb.CustomTagsLiveTest do
  use TransportWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "render and add tags", %{conn: conn} do
    conn = conn |> setup_admin_in_session()

    dataset = insert(:dataset, custom_tags: ["super", "top"])

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.CustomTagsLive,
        session: %{
          "dataset" => dataset,
          "form" => :form
        }
      )

    # render existing tags
    assert render(view) =~ "Ajouter un tag"
    assert render(view) =~ "super"
    assert render(view) =~ "top"

    # add a new tag
    rendered_view =
      view
      |> element("#custom_tag")
      |> render_keydown(%{"key" => "Enter", "value" => " ExCeLlEnT   "})

    assert rendered_view =~ "excellent"
    refute rendered_view =~ "excellent   "
  end
end
