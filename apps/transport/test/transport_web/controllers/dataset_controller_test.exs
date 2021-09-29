defmodule TransportWeb.DatasetControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import DB.Factory

  import Mock

  doctest TransportWeb.DatasetController

  test "GET /", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index))
    assert html_response(conn, 200) =~ "Jeux de données"
  end

  test "Datasets details page loads even when data.gouv is down", %{conn: conn} do
    # NOTE: we just want a dataset, but the factory setup is not finished, so
    # we have to provide an already built aom
    dataset = insert(:dataset, aom: insert(:aom, composition_res_id: 157))

    with_mocks [
      {Datagouvfr.Client.Reuses, [], [get: fn _dataset -> {:error, "data.gouv is down !"} end]},
      {Datagouvfr.Client.Discussions, [], [get: fn _id -> nil end]}
    ] do
      conn = conn |> get(dataset_path(conn, :details, dataset.slug))
      html = html_response(conn, 200)
      assert html =~ "réutilisations sont temporairement indisponibles"
    end
  end

  test "GET /api/datasets has HTTP cache headers set", %{conn: conn} do
    conn = conn |> get(TransportWeb.API.Router.Helpers.dataset_path(conn, :datasets))

    json_response(conn, 200)

    assert conn |> get_resp_header("etag")
    assert conn |> get_resp_header("cache-control") == ["max-age=60, public, must-revalidate"]
  end
end
