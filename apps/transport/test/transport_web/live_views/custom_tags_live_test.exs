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

    # Does not lowercase tags for SIRI requestor refs
    rendered_view =
      view
      |> element("#custom_tag")
      |> render_keydown(%{"key" => "Enter", "value" => "requestor_ref:OPENDATA"})

    assert rendered_view =~ "requestor_ref:OPENDATA"
  end

  test "tags_suggestions includes unique tags in the DB + documented tags" do
    insert(:dataset, is_active: true, custom_tags: ["foo"])
    insert(:dataset, is_active: true, custom_tags: ["foo", "bar"])
    insert(:dataset, is_active: true, is_hidden: true, custom_tags: ["baz"])
    insert(:dataset, is_active: false, custom_tags: ["nope"])

    suggestions = MapSet.new(TransportWeb.CustomTagsLive.tags_suggestions())

    assert MapSet.new(["bar", "baz", "foo"]) |> MapSet.subset?(suggestions)

    documented_tags = Enum.map(TransportWeb.CustomTagsLive.tags_documentation(), & &1.name)
    assert MapSet.new(["bar", "baz", "foo"] ++ documented_tags) |> MapSet.equal?(suggestions)
  end
end
