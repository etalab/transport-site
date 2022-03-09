defmodule TransportWeb.ResourceControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.DatabaseCase, cleanup: [:datasets], async: false
  alias DB.{AOM, Dataset, Resource, Validation}
  import Plug.Test
  import Mox
  import DB.Factory

  setup :verify_on_exit!

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
            url: "http://link.to/angers.zip?foo=bar",
            datagouv_id: "2",
            validation: %Validation{
              details: %{},
              max_error: "Info"
            },
            metadata: %{"networks" => [], "modes" => []},
            format: "GTFS"
          },
          %Resource{
            url: "http://link.to/gbfs",
            datagouv_id: "3",
            metadata: %{"versions" => ["2.2"], "validation" => %{"errors_count" => 1, "has_errors" => true}},
            format: "gbfs"
          },
          %Resource{
            url: "http://link.to/file",
            datagouv_id: "4",
            metadata: %{"validation" => %{"errors_count" => 1, "has_errors" => true, "errors" => ["this is an error"]}},
            schema_name: "etalab/foo",
            format: "json"
          },
          %Resource{
            url: "http://link.to/gtfs-rt",
            datagouv_id: "5",
            metadata: %{"validation" => %{"errors_count" => 2, "warnings_count" => 3}},
            validation: %Validation{
              date: DateTime.utc_now() |> DateTime.to_string(),
              details: %{
                "errors_count" => 2,
                "warnings_count" => 3,
                "files" => %{
                  "gtfs_permanent_url" => "https://example.com/gtfs.zip",
                  "gtfs_rt_permanent_url" => "https://example.com/gtfs-rt"
                },
                "errors" => [
                  %{
                    "title" => "error title",
                    "description" => "error description",
                    "severity" => "ERROR",
                    "error_id" => "E001",
                    "errors_count" => 2,
                    "errors" => ["sample 1", "foo"]
                  },
                  %{
                    "title" => "warning title",
                    "description" => "warning description",
                    "severity" => "WARNING",
                    "error_id" => "W001",
                    "errors_count" => 3,
                    "errors" => ["sample 2", "bar", "baz"]
                  }
                ]
              }
            },
            format: "gtfs-rt"
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

  test "resource without metadata sends back a 200", %{conn: conn} do
    resource = Resource |> Repo.get_by(datagouv_id: "1")
    refute is_nil(resource)
    assert is_nil(resource.metadata)
    conn |> get(resource_path(conn, :details, resource.id)) |> html_response(200)
  end

  test "GTFS resource with metadata sends back a 200", %{conn: conn} do
    resource = Resource |> Repo.get_by(datagouv_id: "2")
    assert resource.format == "GTFS"
    refute is_nil(resource.metadata)
    conn |> get(resource_path(conn, :details, resource.id)) |> html_response(200)
  end

  test "GTFS resource with associated NeTEx", %{conn: conn} do
    resource = Resource |> Repo.get_by(datagouv_id: "2")
    insert(:resource_history, datagouv_id: "2", payload: %{"uuid" => uuid = Ecto.UUID.generate()})

    insert(:data_conversion,
      resource_history_uuid: uuid,
      convert_from: "GTFS",
      convert_to: "NeTEx",
      payload: %{"permanent_url" => url = "https://super-cellar-url.com/netex"}
    )

    html_response = conn |> get(resource_path(conn, :details, resource.id)) |> html_response(200)
    assert html_response =~ "NeTEx"
    assert html_response =~ url
  end

  test "GBFS resource with metadata but no errors sends back a 200", %{conn: conn} do
    resource = Resource |> Repo.get_by(datagouv_id: "3")
    assert resource.format == "gbfs"
    assert Resource.has_errors_details?(resource)
    refute Map.has_key?(resource.metadata["validation"], "errors")
    conn |> get(resource_path(conn, :details, resource.id)) |> html_response(200)
  end

  test "resource with error details sends back a 200", %{conn: conn} do
    resource = Resource |> Repo.get_by(datagouv_id: "4")
    refute is_nil(resource.schema_name)

    Transport.Shared.Schemas.Mock
    |> expect(:transport_schemas, fn -> %{resource.schema_name => %{"title" => "foo"}} end)

    assert Resource.has_errors_details?(resource)
    conn |> get(resource_path(conn, :details, resource.id)) |> html_response(200) |> assert =~ "this is an error"
  end

  test "resource has download availability displayed", %{conn: conn} do
    resource = Resource |> Repo.get_by(datagouv_id: "4")

    Transport.Shared.Schemas.Mock
    |> expect(:transport_schemas, fn -> %{resource.schema_name => %{"title" => "foo"}} end)

    html = conn |> get(resource_path(conn, :details, resource.id)) |> html_response(200)

    assert html =~ "Disponibilité au téléchargement"
    assert html =~ "download_availability_100"
  end

  test "gtfs-rt resource with error details sends back a 200", %{conn: conn} do
    resource = Resource |> preload(:validation) |> Repo.get_by(datagouv_id: "5")
    assert Resource.is_gtfs_rt?(resource)
    assert Resource.has_errors_details?(resource)
    content = conn |> get(resource_path(conn, :details, resource.id)) |> html_response(200)

    [
      "2 erreurs",
      "3 avertissements",
      "error title",
      "E001",
      "warning title",
      "W001",
      "sample 1",
      "sample 2",
      resource.validation.details["files"]["gtfs_permanent_url"],
      resource.validation.details["files"]["gtfs_rt_permanent_url"]
    ]
    |> Enum.each(&assert content =~ &1)
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
    assert ["application/zip"] == conn |> get_resp_header("content-type")
    assert [~s(attachment; filename="angers.zip")] == conn |> get_resp_header("content-disposition")

    assert conn |> response(200) == "payload"
  end

  test "downloading a resource that cannot be directly downloaded with a filename", %{conn: conn} do
    resource = Resource |> Repo.get_by(datagouv_id: "2")
    refute Resource.can_direct_download?(resource)

    Transport.HTTPoison.Mock
    |> expect(:get, fn url, [], hackney: [follow_redirect: true] ->
      assert url == resource.url

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: "payload",
         headers: [{"Content-Type", "application/zip"}, {"Content-Disposition", ~s(attachment; filename="foo.zip")}]
       }}
    end)

    conn = conn |> get(resource_path(conn, :download, resource.id))
    assert ["application/zip"] == conn |> get_resp_header("content-type")
    assert [~s(attachment; filename="foo.zip")] == conn |> get_resp_header("content-disposition")

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
