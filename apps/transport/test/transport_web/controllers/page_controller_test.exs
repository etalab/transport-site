defmodule TransportWeb.PageControllerTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.DatabaseCase, cleanup: []
  import Plug.Test, only: [init_test_session: 2]
  import Mock

  doctest TransportWeb.PageController

  test "GET /", %{conn: conn} do
    conn = conn |> get(page_path(conn, :index))
    assert html_response(conn, 200) =~ "disponible, valoriser et améliorer"
  end

  describe "GET /espace_producteur" do
    test "requires authentication", %{conn: conn} do
      conn =
        conn
        |> get(page_path(conn, :espace_producteur))

      assert redirected_to(conn, 302) =~ "/login"
    end

    test "renders successfully when data gouv returns no error", %{conn: conn} do
      # TODO: use real datasets, but I need a bit of stubbing?
      with_mock Dataset, user_datasets: fn _ -> {:ok, []} end, user_org_datasets: fn _ -> {:ok, []} end do
        conn =
          conn
          |> init_test_session(current_user: %{})
          |> get(page_path(conn, :espace_producteur))

        body = html_response(conn, 200)
        assert body =~ "Mettre à jour un jeu de données"
        assert body =~ "pas de ressource à mettre à jour pour le moment"
        assert !(body =~ "message--error")
      end
    end

    test "renders a degraded mode when data gouv returns error", %{conn: conn} do
      with_mock Dataset, user_datasets: fn _ -> {"BAD"} end, user_org_datasets: fn _ -> {"SOMETHING"} end do
        conn =
          conn
          |> init_test_session(current_user: %{})
          |> get(page_path(conn, :espace_producteur))

        body = html_response(conn, 200)

        {:ok, doc} = Floki.parse_document(body)
        assert Floki.find(doc, ".dataset-item") |> length == 0

        assert Floki.find(doc, ".message--error") |> Floki.text() ==
                 "Une erreur a eu lieu lors de la récupération de vos ressources"
      end
    end
  end
end
