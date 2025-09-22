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
      d1 = insert(:dataset, type: "public-transit")
      d2 = insert(:dataset, type: "private-parking")
      foo = insert(:reuse, title: "Foo", datasets: [d1])
      bar = insert(:reuse, owner: "Bar", datasets: [d2])

      reuse_titles = fn q, type ->
        conn
        |> get(reuse_path(conn, :index), q: q, type: type)
        |> html_response(200)
        |> Floki.parse_document!()
        |> Floki.find(".card__content h3")
        |> Enum.map(&Floki.text/1)
      end

      assert [bar.title, foo.title] == reuse_titles.("", "")
      assert [foo.title] == reuse_titles.("foo", "")
      assert [bar.title] == reuse_titles.("ba", "")
      assert [bar.title] == reuse_titles.("", d2.type)
    end
  end
end
