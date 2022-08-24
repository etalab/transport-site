defmodule TransportWeb.ResourceControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.DatabaseCase, cleanup: [:datasets], async: false
  alias DB.{AOM, Dataset, Resource, Validation}
  import Plug.Test
  import Mox
  import DB.Factory
  import ExUnit.CaptureLog

  setup :verify_on_exit!

  @service_alerts_file "#{__DIR__}/../../fixture/files/bibus-brest-gtfs-rt-alerts.pb"

  setup do
    Mox.stub_with(Transport.DataVisualization.Mock, Transport.DataVisualization.Impl)

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
    insert(:resource_history, resource_id: resource.id, payload: %{"uuid" => uuid = Ecto.UUID.generate()})

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
    |> expect(:schemas_by_type, 1, fn _type -> %{resource.schema_name => %{}} end)

    assert Resource.has_errors_details?(resource)
    conn |> get(resource_path(conn, :details, resource.id)) |> html_response(200) |> assert =~ "this is an error"
  end

  test "resource has download availability displayed", %{conn: conn} do
    resource = Resource |> Repo.get_by(datagouv_id: "4")

    Transport.Shared.Schemas.Mock
    |> expect(:schemas_by_type, 1, fn _type -> %{resource.schema_name => %{}} end)

    html = conn |> get(resource_path(conn, :details, resource.id)) |> html_response(200)

    assert html =~ "Disponibilité au téléchargement"
    assert html =~ "download_availability_100"
  end

  test "gtfs-rt resource with error details sends back a 200", %{conn: conn} do
    resource_url = "xxx"

    validation_result = %{
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

    dataset = insert(:dataset)
    resource = insert(:resource, dataset_id: dataset.id, url: resource_url, format: "gtfs-rt")

    insert(:multi_validation,
      validator: Transport.Validators.GTFSRT.validator_name(),
      resource_id: resource.id,
      validation_timestamp: DateTime.utc_now(),
      result: validation_result
    )

    resource = Resource |> preload(:dataset) |> DB.Repo.get!(resource.id)

    Transport.HTTPoison.Mock
    |> expect(:get, fn ^resource_url, [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 200, body: File.read!(@service_alerts_file)}}
    end)

    assert Resource.is_gtfs_rt?(resource)

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
      validation_result["files"]["gtfs_permanent_url"],
      validation_result["files"]["gtfs_rt_permanent_url"],
      "Prolongation des travaux rue de Kermaria"
    ]
    |> Enum.each(&assert content =~ &1)
  end

  test "gtfs-rt resource with feed decode error", %{conn: conn} do
    %{url: url} = resource = Resource |> preload(:validation) |> Repo.get_by(datagouv_id: "5")

    Transport.HTTPoison.Mock
    |> expect(:get, fn ^url, [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 502, body: ""}}
    end)

    assert Resource.is_gtfs_rt?(resource)
    content = conn |> get(resource_path(conn, :details, resource.id)) |> html_response(200)

    assert content =~ "Impossible de décoder le flux GTFS-RT"
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

  test "flash message when parent dataset is inactive", %{conn: conn} do
    %{id: dataset_id} = insert(:dataset, %{is_active: false})
    %{id: resource_id} = insert(:resource, %{dataset_id: dataset_id, url: "https://example.com/file"})

    conn = conn |> get(resource_path(conn, :details, resource_id))
    assert conn |> html_response(200) =~ "supprimé de data.gouv.fr"
  end

  test "no flash message when parent dataset is active", %{conn: conn} do
    %{id: dataset_id} = insert(:dataset, %{is_active: true})
    %{id: resource_id} = insert(:resource, %{dataset_id: dataset_id, url: "https://example.com/file"})

    conn = conn |> get(resource_path(conn, :details, resource_id))
    refute conn |> html_response(200) =~ "supprimé de data.gouv.fr"
  end

  test "GTFS Transport validation is shown", %{conn: conn} do
    %{id: dataset_id} = insert(:dataset)

    %{id: resource_id} =
      insert(:resource, %{
        dataset_id: dataset_id,
        format: "GTFS",
        datagouv_id: datagouv_id = "datagouv_id",
        url: "https://example.com/file"
      })

    conn1 = conn |> get(resource_path(conn, :details, resource_id))
    assert conn1 |> html_response(200) =~ "Pas de validation disponible"

    %{id: resource_history_id} = insert(:resource_history, %{datagouv_id: datagouv_id})

    insert(:multi_validation, %{
      resource_history_id: resource_history_id,
      validator: Transport.Validators.GTFSTransport.validator_name(),
      result: %{},
      metadata: %{metadata: %{}}
    })

    conn2 = conn |> get(resource_path(conn, :details, resource_id))
    assert conn2 |> html_response(200) =~ "Rapport de validation"
  end

  test "GTFS-RT validation is shown", %{conn: conn} do
    %{id: dataset_id} = insert(:dataset)

    %{id: resource_id} =
      insert(:resource, %{
        dataset_id: dataset_id,
        format: "gtfs-rt",
        url: "https://example.com/file"
      })

    Transport.HTTPoison.Mock
    |> expect(:get, 2, fn _, _, _ -> {:ok, %HTTPoison.Response{status_code: 200, body: ""}} end)

    {conn1, _} = with_log(fn -> conn |> get(resource_path(conn, :details, resource_id)) end)
    assert conn1 |> html_response(200) =~ "Pas de validation disponible"

    %{id: resource_history_id} = insert(:resource_history, %{resource_id: resource_id})

    insert(:multi_validation, %{
      resource_history_id: resource_history_id,
      validator: Transport.Validators.GTFSRT.validator_name(),
      result: %{
        "errors" => [
          %{
            "title" => "oops",
            "severity" => "ERROR",
            "error_id" => "id",
            "errors_count" => 1,
            "description" => "oops",
            "errors" => ["oops"]
          }
        ],
        "has_errors" => true,
        "errors_count" => 1,
        "files" => %{
          "gtfs_permanent_url" => "url",
          "gtfs_rt_permanent_url" => "url"
        }
      },
      metadata: %{metadata: %{}}
    })

    {conn2, _} = with_log(fn -> conn |> get(resource_path(conn, :details, resource_id)) end)
    assert conn2 |> html_response(200) =~ "Rapport de validation"
    assert conn2 |> html_response(200) =~ "1 erreur"
    refute conn2 |> html_response(200) =~ "Pas de validation disponible"
  end

  test "Table Schema validation is shown", %{conn: conn} do
    %{id: dataset_id} = insert(:dataset)

    %{id: resource_id} =
      insert(:resource, %{
        dataset_id: dataset_id,
        format: "csv",
        schema_name: schema_name = "etalab/schema-lieux-covoiturage",
        url: "https://example.com/file"
      })

    Transport.Shared.Schemas.Mock
    |> expect(:schemas_by_type, 2, fn type ->
      case type do
        "tableschema" -> %{schema_name => %{}}
        "jsonschema" -> %{}
      end
    end)

    Transport.Shared.Schemas.Mock
    |> expect(:transport_schemas, 2, fn -> %{schema_name => %{"title" => "foo"}} end)

    conn1 = conn |> get(resource_path(conn, :details, resource_id))
    assert conn1 |> html_response(200) =~ "Pas de validation disponible"

    %{id: resource_history_id} = insert(:resource_history, %{resource_id: resource_id})

    insert(:multi_validation, %{
      resource_history_id: resource_history_id,
      validator: Transport.Validators.TableSchema.validator_name(),
      result: %{"has_errors" => true, "errors_count" => 1, "validation_performed" => true, "errors" => ["oops"]},
      metadata: %{metadata: %{}}
    })

    conn2 = conn |> get(resource_path(conn, :details, resource_id))
    assert conn2 |> html_response(200) =~ "Rapport de validation"
    assert conn2 |> html_response(200) =~ "1 erreur"
    refute conn2 |> html_response(200) =~ "Pas de validation disponible"
  end

  test "JSON Schema validation is shown", %{conn: conn} do
    %{id: dataset_id} = insert(:dataset)

    %{id: resource_id} =
      insert(:resource, %{
        dataset_id: dataset_id,
        format: "csv",
        schema_name: schema_name = "etalab/zfe",
        url: "https://example.com/file"
      })

    Transport.Shared.Schemas.Mock
    |> expect(:schemas_by_type, 4, fn type ->
      case type do
        "tableschema" -> %{}
        "jsonschema" -> %{schema_name => %{}}
      end
    end)

    Transport.Shared.Schemas.Mock
    |> expect(:transport_schemas, 2, fn -> %{schema_name => %{"title" => "foo"}} end)

    conn1 = conn |> get(resource_path(conn, :details, resource_id))
    assert conn1 |> html_response(200) =~ "Pas de validation disponible"

    %{id: resource_history_id} = insert(:resource_history, %{resource_id: resource_id})

    insert(:multi_validation, %{
      resource_history_id: resource_history_id,
      validator: Transport.Validators.EXJSONSchema.validator_name(),
      result: %{"has_errors" => true, "errors_count" => 1, "validation_performed" => true, "errors" => ["oops"]},
      metadata: %{metadata: %{}}
    })

    conn2 = conn |> get(resource_path(conn, :details, resource_id))
    assert conn2 |> html_response(200) =~ "Rapport de validation"
    assert conn2 |> html_response(200) =~ "1 erreur"
    refute conn2 |> html_response(200) =~ "Pas de validation disponible"
  end

  test "does not crash when validation_performed is false", %{conn: conn} do
    %{id: dataset_id} = insert(:dataset)

    %{id: resource_id} =
      insert(:resource, %{
        dataset_id: dataset_id,
        format: "csv",
        schema_name: schema_name = "etalab/zfe",
        url: "https://example.com/file"
      })

    Transport.Shared.Schemas.Mock
    |> expect(:schemas_by_type, 4, fn type ->
      case type do
        "tableschema" -> %{}
        "jsonschema" -> %{schema_name => %{}}
      end
    end)

    conn1 = conn |> get(resource_path(conn, :details, resource_id))
    assert conn1 |> html_response(200) =~ "Pas de validation disponible"

    %{id: resource_history_id} = insert(:resource_history, %{resource_id: resource_id})

    insert(:multi_validation, %{
      resource_history_id: resource_history_id,
      validator: Transport.Validators.EXJSONSchema.validator_name(),
      result: %{"validation_performed" => false}
    })

    conn2 = conn |> get(resource_path(conn, :details, resource_id))
    assert conn2 |> html_response(200) =~ "Pas de validation disponible"
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
