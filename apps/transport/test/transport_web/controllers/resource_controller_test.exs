defmodule TransportWeb.ResourceControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.DatabaseCase, cleanup: [:datasets], async: false
  alias DB.{AOM, Dataset, Resource}
  import Plug.Test
  import Mox

  setup do
    {:ok, _} =
      %Dataset{
        slug: "slug-1",
        resources: [
          %Resource{
            url: "https://link.to/angers.zip",
            datagouv_id: "1"
          },
          %Resource{
            url: "http://link.to/angers.zip",
            datagouv_id: "2"
          }
        ],
        aom: %AOM{id: 4242, nom: "Angers Métropôle"}
      }
      |> Repo.insert()

    :ok
  end

  test "I can see my datasets", %{conn: conn} do
    conn
    |> init_test_session(%{current_user: %{"organizations" => [%{"slug" => "equipe-transport-data-gouv-fr"}]}})
    |> get("/resources/update/datasets")
    |> html_response(200)
  end

  test "Non existing resource raises a Ecto.NoResultsError (interpreted as a 404 thanks to phoenix_ecto)", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn ->
      conn |> get(resource_path(conn, :details, 0))
    end
  end

  test "resource without metadata send back a 404", %{conn: conn} do
    resource = Resource |> Repo.get_by(datagouv_id: "1")
    refute is_nil(resource)
    assert is_nil(resource.metadata)
    conn |> get(resource_path(conn, :details, resource.id)) |> html_response(404) |> assert =~ "404"
  end

  test "downloading a resource that can be directly downloaded", %{conn: conn} do
    resource = Resource |> Repo.get_by(datagouv_id: "1")
    assert Resource.can_direct_download?(resource)

    location = conn |> get(resource_path(conn, :download, resource.id)) |> redirected_to
    assert location == resource.url
  end

  test "downloading a resource that cannot be directly downloaded", %{conn: conn} do
    resource = Resource |> Repo.get_by(datagouv_id: "2")
    refute Resource.can_direct_download?(resource)

    Transport.HTTPoison.Mock
    |> expect(:get, fn url, [], hackney: [follow_redirect: true] ->
      assert url == resource.url
      {:ok, %HTTPoison.Response{status_code: 200, body: "payload", headers: [{"Content-Type", "application/zip"}]}}
    end)

    conn = conn |> get(resource_path(conn, :download, resource.id))
    [content_type] = conn |> get_resp_header("content-type")
    assert content_type == "application/zip"

    assert conn |> response(200) == "payload"
  end

  test "downloading a resource that cannot be directly downloaded, not found case", %{conn: conn} do
    test_remote_download_error(conn, 404)
  end

  test "downloading a resource that cannot be directly downloaded, remote server error case", %{conn: conn} do
    for status_code <- [500, 502] do
      test_remote_download_error(conn, status_code)
    end
  end

  defp test_remote_download_error(%Plug.Conn{} = conn, mock_status_code) do
    resource = Resource |> Repo.get_by(datagouv_id: "2")
    refute Resource.can_direct_download?(resource)

    Transport.HTTPoison.Mock
    |> expect(:get, fn url, [], hackney: [follow_redirect: true] ->
      assert url == resource.url
      {:ok, %HTTPoison.Response{status_code: mock_status_code}}
    end)

    conn = conn |> get(resource_path(conn, :download, resource.id))

    html = html_response(conn, 404)
    assert html =~ "Page non disponible"
    assert get_flash(conn, :error) == "La ressource n'est pas disponible sur le serveur distant"
  end
end
