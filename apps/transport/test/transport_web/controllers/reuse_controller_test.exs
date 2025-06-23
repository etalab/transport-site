defmodule TransportWeb.ReuseControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "index" do
    test "page is displayed", %{conn: conn} do
      insert(:reuse, title: title = "Ma réutilisation")
      assert conn |> get(reuse_path(conn, :index)) |> html_response(200) =~ title
    end

    test "searching reuses", %{conn: conn} do
      foo = insert(:reuse, title: "Foo")
      bar = insert(:reuse, owner: "Bar")

      reuse_titles = fn search ->
        conn
        |> get(reuse_path(conn, :index), q: search)
        |> html_response(200)
        |> Floki.parse_document!()
        |> Floki.find(".card__content h3")
        |> Enum.map(&Floki.text/1)
      end

      assert [bar.title, foo.title] == reuse_titles.("")
      assert [foo.title] == reuse_titles.("foo")
      assert [bar.title] == reuse_titles.("ba")
    end
  end
end
