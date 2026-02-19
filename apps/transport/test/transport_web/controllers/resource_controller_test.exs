defmodule TransportWeb.ResourceControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.DatabaseCase, cleanup: [:datasets], async: false
  import Mox
  import DB.Factory
  import ExUnit.CaptureLog
  import TransportWeb.PaginationHelpers, only: [make_pagination_config: 1]
  import TransportWeb.ResourceController, only: [paginate_netex_results: 2]

  setup :verify_on_exit!

  @service_alerts_file "#{__DIR__}/../../fixture/files/bibus-brest-gtfs-rt-alerts.pb"
  @pan_org_id "5abca8d588ee386ee6ece479"

  setup do
    Mox.stub_with(Transport.DataVisualization.Mock, Transport.DataVisualization.Impl)
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)

    insert(:dataset,
      created_at: DateTime.utc_now(),
      last_update: DateTime.utc_now(),
      slug: "slug-1",
      resources: [
        %DB.Resource{
          last_update: DateTime.utc_now() |> DateTime.add(-6, :hour),
          last_import: DateTime.utc_now() |> DateTime.add(-1, :hour),
          url: "https://link.to/angers.zip",
          datagouv_id: "1",
          format: "GTFS",
          title: "GTFS",
          description: "Une _très_ belle ressource"
        },
        %DB.Resource{
          last_update: DateTime.utc_now() |> DateTime.add(-6, :hour),
          last_import: DateTime.utc_now() |> DateTime.add(-1, :hour),
          url: "http://link.to/angers.zip?foo=bar",
          datagouv_id: "2",
          format: "GTFS"
        },
        %DB.Resource{
          last_update: DateTime.utc_now() |> DateTime.add(-6, :hour),
          last_import: DateTime.utc_now() |> DateTime.add(-1, :hour),
          url: "http://link.to/gbfs",
          datagouv_id: "3",
          format: "gbfs"
        },
        %DB.Resource{
          last_update: DateTime.utc_now() |> DateTime.add(-6, :hour),
          last_import: DateTime.utc_now() |> DateTime.add(-1, :hour),
          url: "http://link.to/file",
          datagouv_id: "4",
          schema_name: "etalab/foo",
          format: "json"
        },
        %DB.Resource{
          last_update: DateTime.utc_now() |> DateTime.add(-6, :hour),
          last_import: DateTime.utc_now() |> DateTime.add(-1, :hour),
          url: "http://link.to/gtfs-rt",
          datagouv_id: "5",
          format: "gtfs-rt"
        }
      ]
    )

    :ok
  end

  test "Non existing resource returns a 404", %{conn: conn} do
    conn = conn |> get(resource_path(conn, :details, 0))

    assert conn |> html_response(404) =~ "Page non disponible"
  end

  test "GBFS resource with multi-validation sends back 200", %{conn: conn} do
    resource = DB.Resource |> DB.Repo.get_by(datagouv_id: "3")
    assert DB.Resource.gbfs?(resource)

    insert(:multi_validation, %{
      resource_history: insert(:resource_history, %{resource_id: resource.id}),
      validator: Transport.Validators.GBFSValidator.validator_name(),
      result: %{"errors_count" => 1},
      metadata: %DB.ResourceMetadata{metadata: %{}}
    })

    Transport.Schemas.Mock |> expect(:transport_schemas, fn -> %{} end)

    conn = conn |> get(resource_path(conn, :details, resource.id))
    assert conn |> html_response(200) =~ "1 erreur"
  end

  test "GBFS resource with nil validation sends back 200", %{conn: conn} do
    resource = DB.Resource |> DB.Repo.get_by(datagouv_id: "3")
    assert DB.Resource.gbfs?(resource)

    insert(:multi_validation, %{
      resource_history: insert(:resource_history, %{resource_id: resource.id}),
      validator: Transport.Validators.GBFSValidator.validator_name(),
      result: nil,
      metadata: %DB.ResourceMetadata{metadata: %{}}
    })

    Transport.Schemas.Mock |> expect(:transport_schemas, fn -> %{} end)

    assert conn |> get(resource_path(conn, :details, resource.id)) |> html_response(200)
  end

  test "resource has its description displayed", %{conn: conn} do
    resource = DB.Resource |> DB.Repo.get_by(datagouv_id: "1")

    assert resource.description == "Une _très_ belle ressource"
    html = conn |> get(resource_path(conn, :details, resource.id)) |> html_response(200)
    assert html =~ "Une <em>très</em> belle ressource"
  end

  test "resource has download availability displayed", %{conn: conn} do
    resource = DB.Resource |> DB.Repo.get_by(datagouv_id: "4")

    Transport.Schemas.Mock
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

    resource = DB.Resource |> preload(:dataset) |> DB.Repo.get!(resource.id)

    Transport.HTTPoison.Mock
    |> expect(:get, fn ^resource_url, [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 200, body: File.read!(@service_alerts_file)}}
    end)

    assert DB.Resource.gtfs_rt?(resource)

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
      "Prolongation des travaux rue de Kermaria",
      "Impossible de déterminer le fichier GTFS à utiliser",
      "Validations précédentes"
    ]
    |> Enum.each(&assert content =~ &1)
  end

  test "gtfs-rt resource with feed decode error", %{conn: conn} do
    %{url: url} = resource = DB.Resource |> DB.Repo.get_by(datagouv_id: "5")

    Transport.HTTPoison.Mock
    |> expect(:get, fn ^url, [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 502, body: ""}}
    end)

    assert DB.Resource.gtfs_rt?(resource)
    content = conn |> get(resource_path(conn, :details, resource.id)) |> html_response(200)

    assert content =~ "Impossible de décoder le flux GTFS-RT"
  end

  test "HEAD request for an HTTP resource", %{conn: conn} do
    resource = DB.Resource |> DB.Repo.get_by(datagouv_id: "2")
    refute DB.Resource.can_direct_download?(resource)

    Transport.HTTPoison.Mock
    |> expect(:head, fn url, [] ->
      assert url == resource.url

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         headers: [
           {"Content-Type", "application/zip"},
           {"foo", "bar"},
           {"transfer-encoding", "chunked"},
           {"date", "date_value"}
         ]
       }}
    end)

    assert %Plug.Conn{assigns: %{original_method: "HEAD"}, resp_body: "", status: 200} =
             conn = conn |> head(resource_path(conn, :download, resource.id))

    assert ["application/zip"] == conn |> get_resp_header("content-type")
    assert ["date_value"] == conn |> get_resp_header("date")
    # Headers absent from the allowlist have been removed
    assert [] == conn |> get_resp_header("foo")
    assert [] == conn |> get_resp_header("transfer-encoding")

    # With a resource that can be directly downloaded
    resource = DB.Resource |> DB.Repo.get_by(datagouv_id: "1")
    assert DB.Resource.can_direct_download?(resource)
    assert conn |> head(resource_path(conn, :download, resource.id)) |> response(404) == ""
  end

  test "downloading a resource that can be directly downloaded", %{conn: conn} do
    resource = DB.Resource |> DB.Repo.get_by(datagouv_id: "1")
    assert DB.Resource.can_direct_download?(resource)

    location = conn |> get(resource_path(conn, :download, resource.id)) |> redirected_to
    assert location == resource.url
  end

  test "downloading a resource that cannot be directly downloaded", %{conn: conn} do
    resource = DB.Resource |> DB.Repo.get_by(datagouv_id: "2")
    refute DB.Resource.can_direct_download?(resource)

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
    resource = DB.Resource |> DB.Repo.get_by(datagouv_id: "2")
    refute DB.Resource.can_direct_download?(resource)

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

  test "HEAD request for a PAN resource", %{conn: conn} do
    dataset = insert(:dataset, organization_id: @pan_org_id)
    resource = insert(:resource, dataset: dataset)

    assert conn |> head(resource_path(conn, :download, resource.id)) |> response(200)
  end

  test "download a PAN resource, invalid token", %{conn: conn} do
    dataset = insert(:dataset, organization_id: @pan_org_id)
    resource = insert(:resource, dataset: dataset)

    assert "You must set a valid Authorization header" ==
             conn
             |> get(resource_path(conn, :download, resource.id, token: "invalid"))
             |> response(401)

    assert [] = DB.ResourceDownload |> DB.Repo.all()
  end

  test "download a PAN resource, no token", %{conn: conn} do
    dataset = insert(:dataset, organization_id: @pan_org_id)

    %DB.Resource{id: resource_id} =
      resource = insert(:resource, dataset: dataset, latest_url: latest_url = "https://example.com/latest_url")

    assert latest_url ==
             conn
             |> get(resource_path(conn, :download, resource.id))
             |> redirected_to(302)

    assert [%DB.ResourceDownload{token_id: nil, resource_id: ^resource_id}] = DB.ResourceDownload |> DB.Repo.all()
  end

  test "download a PAN resource, valid token", %{conn: conn} do
    dataset = insert(:dataset, organization_id: @pan_org_id)

    %DB.Resource{id: resource_id} =
      resource = insert(:resource, dataset: dataset, latest_url: latest_url = "https://example.com/latest_url")

    %DB.Token{id: token_id} = token = insert_token()

    assert latest_url ==
             conn
             |> get(resource_path(conn, :download, resource.id, token: token.secret))
             |> redirected_to(302)

    assert [%DB.ResourceDownload{token_id: ^token_id, resource_id: ^resource_id}] = DB.ResourceDownload |> DB.Repo.all()
  end

  test "HEAD request for a dataset with the experimental tag", %{conn: conn} do
    dataset = insert(:dataset, custom_tags: ["authentification_experimentation"])
    resource = insert(:resource, url: url = "https://example.com/head", dataset: dataset)

    Transport.HTTPoison.Mock
    |> expect(:head, fn ^url, [] ->
      {:ok, %HTTPoison.Response{status_code: 200}}
    end)

    assert conn |> head(resource_path(conn, :download, resource.id)) |> response(200)
  end

  test "download a dataset with the experimental tag, invalid token", %{conn: conn} do
    dataset = insert(:dataset, custom_tags: ["authentification_experimentation"])
    resource = insert(:resource, dataset: dataset)

    assert "You must set a valid Authorization header" ==
             conn
             |> get(resource_path(conn, :download, resource.id, token: "invalid"))
             |> response(401)

    assert [] = DB.ResourceDownload |> DB.Repo.all()
  end

  test "download a dataset with the experimental tag, no token", %{conn: conn} do
    dataset = insert(:dataset, custom_tags: ["authentification_experimentation"])

    %DB.Resource{id: resource_id} =
      resource = insert(:resource, dataset: dataset, latest_url: latest_url = "https://example.com/latest_url")

    assert latest_url ==
             conn
             |> get(resource_path(conn, :download, resource.id))
             |> redirected_to(302)

    assert [%DB.ResourceDownload{token_id: nil, resource_id: ^resource_id}] = DB.ResourceDownload |> DB.Repo.all()
  end

  test "download a dataset with the experimental tag, valid token", %{conn: conn} do
    dataset = insert(:dataset, custom_tags: ["authentification_experimentation"])

    %DB.Resource{id: resource_id} =
      resource = insert(:resource, dataset: dataset, latest_url: latest_url = "https://example.com/latest_url")

    %DB.Token{id: token_id} = token = insert_token()

    assert latest_url ==
             conn
             |> get(resource_path(conn, :download, resource.id, token: token.secret))
             |> redirected_to(302)

    assert [%DB.ResourceDownload{token_id: ^token_id, resource_id: ^resource_id}] = DB.ResourceDownload |> DB.Repo.all()
  end

  test "resource#details, PAN resource, logged-in user with a default token", %{conn: conn} do
    dataset = insert(:dataset, organization_id: @pan_org_id)
    resource = insert(:resource, dataset: dataset)
    assert resource |> DB.Repo.preload(:dataset) |> DB.Resource.pan_resource?()

    contact = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})
    token = insert_token()
    insert(:default_token, contact: contact, token: token)

    assert [resource_url(TransportWeb.Endpoint, :download, resource.id, token: token.secret)] ==
             conn
             |> Phoenix.ConnTest.init_test_session(%{current_user: %{"id" => datagouv_user_id}})
             |> resource_href_download_button(resource)
  end

  test "resource#details, PAN resource, logged-in user without a default token", %{conn: conn} do
    dataset = insert(:dataset, organization_id: @pan_org_id)
    resource = insert(:resource, dataset: dataset)
    assert resource |> DB.Repo.preload(:dataset) |> DB.Resource.pan_resource?()

    organization = insert(:organization)

    insert_contact(%{
      datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
      organizations: [organization |> Map.from_struct()]
    })

    insert_token(%{organization_id: organization.id})

    assert [resource_url(TransportWeb.Endpoint, :download, resource.id)] ==
             conn
             |> Phoenix.ConnTest.init_test_session(%{current_user: %{"id" => datagouv_user_id}})
             |> resource_href_download_button(resource)
  end

  test "resource#details, PAN resource, logged-out user", %{conn: conn} do
    dataset = insert(:dataset, organization_id: @pan_org_id)
    resource = insert(:resource, dataset: dataset)
    assert resource |> DB.Repo.preload(:dataset) |> DB.Resource.pan_resource?()

    assert [resource_url(TransportWeb.Endpoint, :download, resource.id)] ==
             conn |> resource_href_download_button(resource)
  end

  test "resource#details, dataset with experimentation tag, logged-in user with a default token", %{conn: conn} do
    dataset = insert(:dataset, custom_tags: ["authentification_experimentation"])
    resource = insert(:resource, dataset: dataset)

    contact = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})
    token = insert_token()
    insert(:default_token, contact: contact, token: token)

    assert [resource_url(TransportWeb.Endpoint, :download, resource.id, token: token.secret)] ==
             conn
             |> Phoenix.ConnTest.init_test_session(%{current_user: %{"id" => datagouv_user_id}})
             |> resource_href_download_button(resource)
  end

  test "resource#details, dataset with experimentation tag, logged-in user without a default token", %{conn: conn} do
    dataset = insert(:dataset, custom_tags: ["authentification_experimentation"])
    resource = insert(:resource, dataset: dataset)

    organization = insert(:organization)

    insert_contact(%{
      datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
      organizations: [organization |> Map.from_struct()]
    })

    insert_token(%{organization_id: organization.id})

    assert [resource_url(TransportWeb.Endpoint, :download, resource.id)] ==
             conn
             |> Phoenix.ConnTest.init_test_session(%{current_user: %{"id" => datagouv_user_id}})
             |> resource_href_download_button(resource)
  end

  test "resource#details, dataset with experimentation tag, logged-out user", %{conn: conn} do
    dataset = insert(:dataset, custom_tags: ["authentification_experimentation"])
    resource = insert(:resource, dataset: dataset)

    assert [resource_url(TransportWeb.Endpoint, :download, resource.id)] ==
             conn |> resource_href_download_button(resource)
  end

  test "resource#details, proxy resource, logged-in user with a default token", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, dataset: dataset, url: "https://proxy.transport.data.gouv.fr/#{Ecto.UUID.generate()}")
    assert resource |> DB.Resource.served_by_proxy?()

    contact = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})
    token = insert_token()
    insert(:default_token, contact: contact, token: token)

    assert [resource.url <> "?token=#{token.secret}"] ==
             conn
             |> Phoenix.ConnTest.init_test_session(%{current_user: %{"id" => datagouv_user_id}})
             |> resource_href_download_button(resource)
  end

  test "resource#details, proxy resource, logged-in user without a default token", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, dataset: dataset, url: "https://proxy.transport.data.gouv.fr/#{Ecto.UUID.generate()}")
    assert resource |> DB.Resource.served_by_proxy?()

    organization = insert(:organization)

    insert_contact(%{
      datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
      organizations: [organization |> Map.from_struct()]
    })

    insert_token(%{organization_id: organization.id})

    assert [resource.url] ==
             conn
             |> Phoenix.ConnTest.init_test_session(%{current_user: %{"id" => datagouv_user_id}})
             |> resource_href_download_button(resource)
  end

  test "resource#details, proxy resource, logged-out user", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, dataset: dataset, url: "https://proxy.transport.data.gouv.fr/#{Ecto.UUID.generate()}")
    assert resource |> DB.Resource.served_by_proxy?()

    assert [resource.url] == conn |> resource_href_download_button(resource)
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

  test "no validation report section for documentation resources", %{conn: conn} do
    resource =
      insert(:resource, %{
        dataset: insert(:dataset),
        format: "pdf",
        url: "https://example.com/file",
        type: "documentation"
      })

    assert DB.Resource.documentation?(resource)

    refute conn |> get(resource_path(conn, :details, resource.id)) |> html_response(200) =~ "Rapport de validation"
  end

  test "GTFS Transport validation is shown", %{conn: conn} do
    items = page_size() * 2 + 1

    for params <- gtfs_params("MissingCoordinates") do
      %{id: dataset_id} = insert(:dataset)

      %{id: resource_id} =
        insert(:resource, %{
          dataset_id: dataset_id,
          format: "GTFS",
          url: "https://example.com/file"
        })

      conn1 = conn |> get(resource_path(conn, :details, resource_id))
      assert conn1 |> html_response(200) =~ "Pas de validation disponible"

      %{id: resource_history_id} =
        insert(:resource_history, %{
          resource_id: resource_id,
          payload: %{"permanent_url" => permanent_url = "https://example.com/#{Ecto.UUID.generate()}"}
        })

      result = %{
        "NullDuration" => [%{"severity" => "Information"}] |> repeated(items),
        "MissingCoordinates" => [%{"severity" => "Warning"}] |> repeated(items)
      }

      %{metadata: metadata} =
        insert(:multi_validation, %{
          resource_history_id: resource_history_id,
          validator: Transport.Validators.GTFSTransport.validator_name(),
          result: result,
          max_error: "Warning",
          metadata: %DB.ResourceMetadata{
            metadata: %{
              "networks" => ["3CM", "RLV"],
              "networks_start_end_dates" => %{
                "3CM" => %{
                  "end_date" => "2022-09-30",
                  "start_date" => "2021-03-05"
                },
                "RLV" => %{
                  end_date: "2022-11-20",
                  start_date: "2022-08-29"
                }
              },
              "stats" => %{
                "stop_points_count" => 1_322,
                "stop_areas_count" => 30,
                "routes_count" => 123,
                "routes_with_short_name_count" => 5
              }
            },
            modes: ["ferry"]
          },
          validation_timestamp: ~U[2022-10-28 14:12:29.041243Z]
        })

      content = conn |> get(resource_path(conn, :details, resource_id, params)) |> html_response(200)
      assert content =~ "Rapport de validation"
      assert content =~ "ferry"
      assert content =~ ~r"nombre de lignes :(\s*)<strong>123</strong>"
      assert content =~ ~r"nombre d&#39;arrêts :(\s*)<strong>1 322</strong>"
      assert content =~ ~r"nombre de zones d&#39;arrêts :(\s*)<strong>30</strong>"
      assert content =~ "couverture calendaire par réseau"
      assert content =~ "3CM"
      assert content =~ "30/09/2022"

      assert content =~
               ~s{Validation effectuée en utilisant <a href="#{permanent_url}">le fichier GTFS en vigueur</a> le 28/10/2022 à 16h12 Europe/Paris}

      [
        # Features are displayed in a table
        {"table", [{"class", _}],
         [
           {"thead", [],
            [
              {"tr", [],
               [
                 {"th", [], ["Description"]},
                 {"th", [], ["Fichier ou champ"]},
                 {"th", [], ["Statut"]},
                 {"th", [], ["Quantité"]}
               ]}
            ]},
           {"tbody", [], rows}
         ]},
        # Issues are listed in a paginated table
        {"table", [{"class", "table"}],
         [
           {"tr", [],
            [
              {"th", [], ["Type d'objet"]},
              {"th", [], ["Identifiant"]},
              {"th", [], ["Nom de l’objet"]},
              {"th", [], ["Identifiant associé"]},
              {"th", [], ["Détails"]}
            ]}
           | list
         ]}
      ] = content |> Floki.parse_document!() |> Floki.find("table")

      assert page_size() == Enum.count(list)

      assert {"tr", [],
              [
                {"td", [], ["Nom court ou n° de la ligne"]},
                {"td", [{"lang", "en"}], [{"code", [], ["routes.txt"]}, " — ", {"code", [], ["route_short_name"]}]},
                {"td", [], ["✅"]},
                {"td", [], ["5"]}
              ]} in rows

      # we remove "networks_start_end_dates" content
      DB.Repo.update!(
        Ecto.Changeset.change(metadata, %{metadata: %{"networks_start_end_dates" => nil, "networks" => ["foo", "bar"]}})
      )

      refute conn
             |> get(resource_path(conn, :details, resource_id, params))
             |> html_response(200) =~ "couverture calendaire par réseau"
    end
  end

  test "NeTEx validation is shown", %{conn: conn} do
    items = page_size() * 2 + 1

    issues =
      [
        %{
          "code" => "xsd-1871",
          "message" =>
            "Element '{http://www.netex.org.uk/netex}OppositeDIrectionRef': This element is not expected. Expected is ( {http://www.netex.org.uk/netex}OppositeDirectionRef ).",
          "criticity" => "error"
        }
      ]
      |> repeated(items)

    for version <- ["0.1.0", "0.2.0", "0.2.1"],
        params <- netex_params_for(version) do
      %{id: dataset_id} = insert(:dataset)

      %{id: resource_id} =
        insert(:resource, %{
          dataset_id: dataset_id,
          format: "NeTEx",
          url: "https://example.com/file"
        })

      url = resource_path(conn, :details, resource_id)
      conn1 = conn |> get(url, params)
      assert conn1 |> html_response(200) =~ "Pas de validation disponible"

      %{id: resource_history_id} =
        insert(:resource_history, %{
          resource_id: resource_id,
          payload: %{"permanent_url" => permanent_url = "https://example.com/#{Ecto.UUID.generate()}"}
        })

      result =
        case version do
          "0.1.0" -> %{"xsd-1871" => issues}
          _ -> %{"xsd-schema" => issues}
        end

      results_adapter = Transport.Validators.NeTEx.ResultsAdapter.resolve(version)

      networks = ["Réseau urbain", "Réseau inter-urbain"]
      modes = ["bus", "ferry"]

      insert(:multi_validation, %{
        resource_history_id: resource_history_id,
        validator: Transport.Validators.NeTEx.Validator.validator_name(),
        validator_version: version,
        digest: results_adapter.digest(result),
        binary_result: results_adapter.to_binary_result(result),
        max_error: "error",
        metadata: %DB.ResourceMetadata{
          metadata: %{"elapsed_seconds" => 42, "networks" => networks, "modes" => modes},
          modes: modes,
          features: []
        },
        validation_timestamp: ~U[2022-10-28 14:12:29.041243Z]
      })

      url = resource_path(conn, :details, resource_id)
      content = conn |> get(url, params) |> html_response(200)
      assert content =~ "Rapport de validation"

      assert content =~
               ~s{Validation effectuée en utilisant <a href="#{permanent_url}">le fichier NeTEx en vigueur</a> le 28/10/2022 à 16h12 Europe/Paris}

      rows = content |> Floki.parse_document!() |> Floki.find("table tr.message")

      assert page_size() == Enum.count(rows)

      assert content =~ "réseaux"
      assert content =~ "Réseau urbain, Réseau inter-urbain"

      assert content =~ "modes de transport"
      assert content =~ "bus, ferry"
    end
  end

  test "GTFS-RT validation is shown", %{conn: conn} do
    %{id: dataset_id} = insert(:dataset)
    %{id: gtfs_id} = insert(:resource, format: "GTFS", dataset_id: dataset_id)

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
    # Even without a multi-validation we can validate now as we have a single GTFS resource
    assert conn1 |> html_response(200) =~ "Valider ce GTFS-RT maintenant"

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
        "ignore_shapes" => true,
        "files" => %{
          "gtfs_permanent_url" => "url",
          "gtfs_rt_permanent_url" => "url"
        }
      },
      secondary_resource_id: gtfs_id,
      metadata: %DB.ResourceMetadata{metadata: %{}}
    })

    {conn2, _} = with_log(fn -> conn |> get(resource_path(conn, :details, resource_id)) end)
    assert conn2 |> html_response(200) =~ "Rapport de validation"
    assert conn2 |> html_response(200) =~ "1 erreur"
    assert conn2 |> html_response(200) =~ "Les shapes présentes dans le GTFS ont été ignorées"
    assert conn2 |> html_response(200) =~ "Valider ce GTFS-RT maintenant"
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

    Transport.Schemas.Mock
    |> expect(:schemas_by_type, 3, fn type ->
      case type do
        "tableschema" -> %{schema_name => %{}}
        "jsonschema" -> %{}
      end
    end)

    Transport.Schemas.Mock
    |> expect(:transport_schemas, 2, fn -> %{schema_name => %{"title" => "foo"}} end)

    conn1 = conn |> get(resource_path(conn, :details, resource_id))
    assert conn1 |> html_response(200) =~ "Pas de validation disponible"

    insert(:multi_validation, %{
      resource_history:
        insert(:resource_history, %{resource_id: resource_id, payload: %{"schema_name" => schema_name}}),
      validator: Transport.Validators.TableSchema.validator_name(),
      result: %{"has_errors" => true, "errors_count" => 1, "validation_performed" => true, "errors" => ["oops"]},
      metadata: %DB.ResourceMetadata{metadata: %{}}
    })

    response = conn |> get(resource_path(conn, :details, resource_id))
    assert response |> html_response(200) =~ "Rapport de validation"
    assert response |> html_response(200) =~ "1 erreur"
    assert response |> html_response(200) =~ "oops"
    refute response |> html_response(200) =~ "Pas de validation disponible"
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

    Transport.Schemas.Mock
    |> expect(:schemas_by_type, 6, fn type ->
      case type do
        "tableschema" -> %{}
        "jsonschema" -> %{schema_name => %{}}
      end
    end)

    Transport.Schemas.Mock
    |> expect(:transport_schemas, 2, fn -> %{schema_name => %{"title" => "foo"}} end)

    conn1 = conn |> get(resource_path(conn, :details, resource_id))
    assert conn1 |> html_response(200) =~ "Pas de validation disponible"

    insert(:multi_validation, %{
      resource_history:
        insert(:resource_history, %{resource_id: resource_id, payload: %{"schema_name" => schema_name}}),
      validator: Transport.Validators.JSONSchema.validator_name(),
      result: %{"has_errors" => true, "errors_count" => 1, "validation_performed" => true, "errors" => ["oops"]},
      metadata: %DB.ResourceMetadata{metadata: %{}}
    })

    response = conn |> get(resource_path(conn, :details, resource_id))
    assert response |> html_response(200) =~ "Rapport de validation"
    assert response |> html_response(200) =~ "1 erreur"
    assert response |> html_response(200) =~ "oops"
    refute response |> html_response(200) =~ "Pas de validation disponible"
  end

  test "GTFS-Flex validation is shown", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, format: "GTFS", dataset: dataset)

    rh =
      insert(:resource_history,
        resource: resource,
        payload: %{
          "format" => "GTFS",
          "filenames" => ["locations.geojson", "stops.txt"],
          "permanent_url" => "https://example.com/gtfs"
        }
      )

    assert DB.ResourceHistory.gtfs_flex?(rh)

    result = %{
      "notices" => [
        %{
          "code" => "unusable_trip",
          "sampleNotices" => [%{"foo" => "bar"}],
          "severity" => "WARNING",
          "totalNotices" => 1
        }
      ],
      "summary" => %{"validatorVersion" => "4.2.0"}
    }

    insert(:multi_validation, %{
      resource_history: rh,
      validator: Transport.Validators.MobilityDataGTFSValidator.validator_name(),
      metadata: %DB.ResourceMetadata{
        metadata: %{"start_date" => "2025-12-01", "end_date" => "2025-12-31"},
        features: ["Bike Allowed"]
      },
      result: result,
      digest: Transport.Validators.MobilityDataGTFSValidator.digest(result),
      max_error: "WARNING"
    })

    response = conn |> get(resource_path(conn, :details, resource.id))

    # Resource metadata
    assert response |> html_response(200) =~ "01/12/2025"
    assert response |> html_response(200) =~ "31/12/2025"
    assert response |> html_response(200) =~ "Bike Allowed"

    # Validation
    assert response |> html_response(200) =~ "Rapport de validation"
    assert response |> html_response(200) =~ "1 avertissement"
    assert response |> html_response(200) =~ "unusable_trip"
    refute response |> html_response(200) =~ "Pas de validation disponible"
  end

  test "GTFS-Flex with empty dates", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, format: "GTFS", dataset: dataset)

    rh =
      insert(:resource_history,
        resource: resource,
        payload: %{
          "format" => "GTFS",
          "filenames" => ["locations.geojson", "stops.txt"],
          "permanent_url" => "https://example.com/gtfs"
        }
      )

    assert DB.ResourceHistory.gtfs_flex?(rh)

    result = %{
      "notices" => [
        %{
          "code" => "unusable_trip",
          "sampleNotices" => [%{"foo" => "bar"}],
          "severity" => "WARNING",
          "totalNotices" => 2
        }
      ],
      "summary" => %{"validatorVersion" => "4.2.0"}
    }

    insert(:multi_validation, %{
      resource_history: rh,
      validator: Transport.Validators.MobilityDataGTFSValidator.validator_name(),
      metadata: %DB.ResourceMetadata{
        metadata: %{"start_date" => "", "end_date" => ""},
        features: ["Bike Allowed"]
      },
      result: result,
      digest: Transport.Validators.MobilityDataGTFSValidator.digest(result),
      max_error: "WARNING"
    })

    response = conn |> get(resource_path(conn, :details, resource.id))

    # Resource metadata
    assert response |> html_response(200) =~ "Bike Allowed"

    # Validation
    assert response |> html_response(200) =~ "Rapport de validation"
    assert response |> html_response(200) =~ "2 avertissements"
    assert response |> html_response(200) =~ "unusable_trip"
  end

  test "GTFS-Flex with lists as sampleNotices", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, format: "GTFS", dataset: dataset)

    rh =
      insert(:resource_history,
        resource: resource,
        payload: %{
          "format" => "GTFS",
          "filenames" => ["locations.geojson", "stops.txt"],
          "permanent_url" => "https://example.com/gtfs"
        }
      )

    assert DB.ResourceHistory.gtfs_flex?(rh)

    result = %{
      "notices" => [
        %{
          "code" => "stop_too_far_from_shape_using_user_distance",
          "severity" => "WARNING",
          "totalNotices" => 2,
          "sampleNotices" => [
            %{
              "match" => [
                43.410709,
                3.678308
              ],
              "stopId" => "SETCGAU1",
              "tripId" => "93360_260105-5359",
              "shapeId" => "260105-102",
              "stopName" => "Charles De Gaulle",
              "tripCsvRowNumber" => 1_907,
              "geoDistanceToShape" => 106.89965062036212,
              "stopTimeCsvRowNumber" => 41_357
            }
          ]
        }
      ],
      "summary" => %{"validatorVersion" => "4.2.0"}
    }

    insert(:multi_validation, %{
      resource_history: rh,
      validator: Transport.Validators.MobilityDataGTFSValidator.validator_name(),
      result: result,
      digest: Transport.Validators.MobilityDataGTFSValidator.digest(result),
      max_error: "WARNING"
    })

    response = conn |> get(resource_path(conn, :details, resource.id))

    # Validation
    assert response |> html_response(200) =~ "Rapport de validation"
    assert response |> html_response(200) =~ "2 avertissements"
    assert response |> html_response(200) =~ "stop_too_far_from_shape_using_user_distance"
    assert response |> html_response(200) =~ "[43.410709, 3.678308]"
  end

  test "displays MobilityData if validated by both GTFS validators", %{conn: conn} do
    dataset = insert(:dataset)
    resource = insert(:resource, format: "GTFS", dataset: dataset)

    rh =
      insert(:resource_history,
        resource: resource,
        payload: %{
          "format" => "GTFS",
          "filenames" => ["locations.geojson", "stops.txt"],
          "permanent_url" => "https://example.com/gtfs"
        }
      )

    assert DB.ResourceHistory.gtfs_flex?(rh)

    result = %{
      "notices" => [
        %{
          "code" => "unusable_trip",
          "sampleNotices" => [%{"foo" => "bar"}],
          "severity" => "WARNING",
          "totalNotices" => 1
        }
      ],
      "summary" => %{"validatorVersion" => "4.2.0"}
    }

    insert(:multi_validation, %{
      resource_history: rh,
      validator: Transport.Validators.MobilityDataGTFSValidator.validator_name(),
      result: result,
      digest: Transport.Validators.MobilityDataGTFSValidator.digest(result),
      max_error: "WARNING"
    })

    insert(:multi_validation, %{
      resource_history: rh,
      validator: Transport.Validators.GTFSTransport.validator_name(),
      result: nil,
      max_error: "Warning"
    })

    response = conn |> get(resource_path(conn, :details, resource.id))

    assert response |> html_response(200) =~ "Rapport de validation"
    assert response |> html_response(200) =~ "1 avertissement"
    assert response |> html_response(200) =~ "unusable_trip"
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

    Transport.Schemas.Mock
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
      validator: Transport.Validators.JSONSchema.validator_name(),
      result: %{"validation_performed" => false}
    })

    conn2 = conn |> get(resource_path(conn, :details, resource_id))
    assert conn2 |> html_response(200) =~ "Pas de validation disponible"
  end

  test "gtfs-rt entities" do
    resource = %{id: resource_id} = insert(:resource, format: "gtfs-rt")
    insert(:resource_metadata, resource_id: resource_id, features: ["b"])
    insert(:resource_metadata, resource_id: resource_id, features: ["a", "d"])
    insert(:resource_metadata, resource_id: resource_id, features: ["c"])
    # too old
    insert(:resource_metadata, resource_id: resource_id, features: ["e"], inserted_at: ~U[2020-01-01 00:00:00Z])

    # we want a sorted list in the output!
    assert ["a", "b", "c", "d"] = TransportWeb.ResourceController.gtfs_rt_entities(resource)
  end

  test "SIRI RequestorRef is displayed", %{conn: conn} do
    requestor_ref_value = Ecto.UUID.generate()

    resource =
      insert(:resource,
        format: "SIRI",
        url: "https://example.com/siri",
        dataset: insert(:dataset, custom_tags: ["requestor_ref:#{requestor_ref_value}", "foo"])
      )

    assert DB.Resource.siri?(resource)
    assert requestor_ref_value == DB.Resource.requestor_ref(resource)

    html = conn |> get(resource_path(conn, :details, resource.id)) |> html_response(200)
    assert html =~ ~s{<h2 id="siri-authentication">Authentification SIRI</h2>}
    assert html =~ requestor_ref_value
  end

  test "latest_validations_details" do
    resource = insert(:resource, format: "gtfs-rt")

    insert(:multi_validation,
      validator: Transport.Validators.GTFSRT.validator_name(),
      resource_id: resource.id,
      validation_timestamp: DateTime.utc_now() |> DateTime.add(-500),
      result: %{
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
    )

    insert(:multi_validation,
      validator: Transport.Validators.GTFSRT.validator_name(),
      resource_id: resource.id,
      validation_timestamp: DateTime.utc_now(),
      result: %{
        "errors" => [
          %{
            "title" => "error title",
            "description" => "error description",
            "severity" => "ERROR",
            "error_id" => "E001",
            "errors_count" => 1,
            "errors" => ["sample 1"]
          },
          %{
            "title" => "error title",
            "description" => "error description 002",
            "severity" => "ERROR",
            "error_id" => "E002",
            "errors_count" => 2,
            "errors" => ["sample 1", "sample 2"]
          }
        ]
      }
    )

    assert %{
             "E001" => %{
               "description" => "error description",
               "errors_count" => 3,
               "occurence" => 2,
               "percentage" => 100
             },
             "E002" => %{
               "description" => "error description 002",
               "errors_count" => 2,
               "occurence" => 1,
               "percentage" => 50
             },
             "W001" => %{
               "description" => "warning description",
               "errors_count" => 3,
               "occurence" => 1,
               "percentage" => 50
             }
           } == TransportWeb.ResourceController.latest_validations_details(resource)
  end

  test "resources_related are displayed", %{conn: conn} do
    %{url: gtfs_url} = gtfs_rt_resource = DB.Repo.get_by(DB.Resource, datagouv_id: "5", format: "gtfs-rt")
    gtfs_resource = DB.Repo.get_by(DB.Resource, datagouv_id: "1", format: "GTFS")

    insert(:resource_related, resource_src: gtfs_rt_resource, resource_dst: gtfs_resource, reason: :gtfs_rt_gtfs)

    expect(Transport.HTTPoison.Mock, :get, fn ^gtfs_url, [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 200, body: ""}}
    end)

    {html_response, _logs} =
      with_log(fn -> conn |> get(resource_path(conn, :details, gtfs_rt_resource.id)) |> html_response(200) end)

    assert html_response =~ ~s(<h2 id="related-resources">Ressources associées</h2>)
    assert html_response =~ "Fichier GTFS associé"
  end

  test "resource size and link to explore.data.gouv.fr are displayed", %{conn: conn} do
    resource = insert(:resource, format: "csv", dataset: insert(:dataset, is_active: true))
    insert(:resource_history, resource_id: resource.id, payload: %{"filesize" => "1024"})

    html_response = conn |> get(resource_path(conn, :details, resource.id)) |> html_response(200)
    assert html_response =~ "Taille : 1 KB"

    assert TransportWeb.ResourceView.eligible_for_explore?(resource)
    assert html_response =~ "https://explore.data.gouv.fr"
  end

  test "NeTEx pagination" do
    config = make_pagination_config(%{})

    total_pages_for_items = fn items ->
      paginate_netex_results({items, repeated([{}], items)}, config).total_pages
    end

    assert 0 == total_pages_for_items.(0)
    assert 1 == total_pages_for_items.(20)
    assert 2 == total_pages_for_items.(22)
    assert 2 == total_pages_for_items.(30)
    assert 3 == total_pages_for_items.(41)
  end

  defp test_remote_download_error(%Plug.Conn{} = conn, mock_status_code) do
    resource = DB.Resource |> DB.Repo.get_by(datagouv_id: "2")
    refute DB.Resource.can_direct_download?(resource)

    Transport.HTTPoison.Mock
    |> expect(:get, fn url, [], hackney: [follow_redirect: true] ->
      assert url == resource.url
      {:ok, %HTTPoison.Response{status_code: mock_status_code}}
    end)

    conn = conn |> get(resource_path(conn, :download, resource.id))

    html = html_response(conn, 404)
    assert html =~ "Page non disponible"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "La ressource n'est pas disponible sur le serveur distant"
  end

  def resource_href_download_button(%Plug.Conn{} = conn, %DB.Resource{} = resource) do
    conn
    |> get(resource_path(conn, :details, resource.id))
    |> html_response(200)
    |> Floki.parse_document!()
    |> Floki.find(".button-outline.small.secondary")
    |> hd()
    |> Floki.attribute("href")
  end

  defp gtfs_params(issue_type) do
    expand_paginated_params([%{}, %{"issue_type" => issue_type}])
  end

  defp netex_params_for(version) do
    filtered_params =
      case version do
        "0.1.0" -> %{"issue_type" => "xsd-1871"}
        _ -> %{"issues_category" => "xsd-schema"}
      end

    expand_paginated_params([%{}, filtered_params])
  end

  defp expand_paginated_params(all_params) do
    for params <- all_params,
        page <- [nil, 1, 2] do
      if is_nil(page) do
        params
      else
        Map.merge(%{"page" => page}, params)
      end
    end
  end

  defp repeated(enumerable, times) do
    enumerable
    |> Stream.cycle()
    |> Enum.take(times)
  end

  defp page_size do
    TransportWeb.PaginationHelpers.make_pagination_config(%{}).page_size
  end
end
