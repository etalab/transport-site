defmodule TransportWeb.BackofficeControllerTest do
  use Oban.Testing, repo: DB.Repo
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  alias DB.{Repo, Resource}

  import Mox
  setup :verify_on_exit!

  setup do
    Mox.stub_with(Datagouvfr.Client.CommunityResources.Mock, Datagouvfr.Client.StubCommunityResources)
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)

    # ressource.db now uses Transport.Shared.Wrapper.HTTPoison instead of HTTPoison directly
    # we stub the mock with the real module here to keep the tests of this file unchanged.
    Mox.stub_with(Transport.HTTPoison.Mock, HTTPoison)
    Mox.stub_with(Shared.Validation.Validator.Mock, Shared.Validation.GtfsValidator)
    Mox.stub_with(Transport.AvailabilityChecker.Mock, Transport.AvailabilityChecker.Dummy)
    Mox.stub_with(Hasher.Mock, Hasher.Dummy)
    Mox.stub_with(Datagouvfr.Authentication.Mock, Datagouvfr.Authentication.Dummy)
    Mox.stub_with(Datagouvfr.Client.User.Mock, Datagouvfr.Client.User.Dummy)
    Mox.stub_with(Transport.DataVisualization.Mock, Transport.DataVisualization.Impl)
    # Using the real implementation for the moment, then it falls back on `HTTPoison.Mock`
    Mox.stub_with(Datagouvfr.Client.Datasets.Mock, Datagouvfr.Client.Datasets.External)
    :ok
  end

  @dataset_url "https://demo.data.gouv.fr/fr/datasets/horaires-theoriques-du-reseau-de-transport-tag-1/"
  @dataset %{
    "url" => @dataset_url,
    "custom_title" => "Grenoble",
    "region_id" => 1,
    "insee" => "38185",
    "type" => "public-transit",
    "action" => "new"
  }

  test "Deny access to backoffice if not logged", %{conn: conn} do
    conn = get(conn, backoffice_page_path(conn, :index))
    target_uri = URI.parse(redirected_to(conn, 302))
    assert target_uri.path == "/login/explanation"
    assert target_uri.query == URI.encode_query(redirect_path: "/backoffice")
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Vous devez être préalablement connecté"
  end

  test "Check that you are an admin", %{conn: conn} do
    contact = DB.Factory.insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

    conn =
      conn
      |> init_test_session(%{current_user: %{"is_admin" => false, "id" => contact.datagouv_user_id}})
      |> get(backoffice_page_path(conn, :index))

    assert redirected_to(conn, 302) =~ "/login/explanation"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
             "Vous devez être un membre de l'équipe transport.data.gouv.fr."
  end

  test "Show 'add new dataset' form", %{conn: conn} do
    conn = conn |> setup_admin_in_session() |> get(backoffice_page_path(conn, :index))
    assert html_response(conn, 200) =~ "Ajouter un jeu de données"
  end

  test "Add a dataset", %{conn: conn} do
    dataset_datagouv_id = "12"
    dataset = @dataset

    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, _url, _, _, _ ->
      {:ok, %HTTPoison.Response{body: %{"id" => dataset_datagouv_id} |> Jason.encode!(), status_code: 200}}
    end)

    Transport.HTTPoison.Mock
    |> expect(:get!, fn "https://demo.data.gouv.fr/api/1/datasets/12/", [], _ ->
      body =
        %{
          "id" => dataset_datagouv_id,
          "slug" => "dataset-slug",
          "type" => "public-transit",
          "resources" => [
            %{
              "last_modified" => DateTime.utc_now() |> DateTime.to_iso8601(),
              "url" => "url1",
              "id" => "resource_datagouv_id",
              "format" => "siri",
              "type" => "main"
            }
          ]
        }
        |> DB.Factory.datagouv_dataset_response()
        |> Jason.encode!()

      %HTTPoison.Response{body: body, status_code: 200}
    end)

    # we fetch 2 community resources
    Datagouvfr.Client.CommunityResources.Mock
    |> expect(:get, fn _dataset_id ->
      {:ok,
       [
         %{
           "url" => "url2",
           "last_modified" => DateTime.utc_now() |> DateTime.to_iso8601(),
           "format" => "json",
           "id" => "resource_datagouv_id_2",
           "type" => "main"
         },
         %{
           "url" => "url3",
           "last_modified" => DateTime.utc_now() |> DateTime.to_iso8601(),
           "format" => "csv",
           "id" => "resource_datagouv_id_3",
           "type" => "main"
         }
       ]}
    end)

    conn = conn |> setup_admin_in_session() |> post(backoffice_dataset_path(conn, :post), %{"form" => dataset})

    assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
    assert Resource |> where([r], not r.is_community_resource) |> Repo.all() |> length() == 1
    assert Resource |> where([r], r.is_community_resource) |> Repo.all() |> length() == 2
    assert ["Dataset ajouté" | _] = Phoenix.Flash.get(conn.assigns.flash, :info)
  end

  test "Add a dataset twice", %{conn: conn} do
    conn = conn |> setup_admin_in_session()

    resource_url = "http://www.metromobilite.fr/data/Horaires/SEM-GTFS.zip"
    dataset = %{@dataset | "region_id" => nil}

    use_cassette "dataset/dataset_twice" do
      conn = post(conn, backoffice_dataset_path(conn, :post), %{"form" => dataset})
      query = from(r in Resource, where: r.url == ^resource_url)
      assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
      assert query |> Repo.all() |> length() == 1

      conn = post(conn, backoffice_dataset_path(conn, :post), %{"form" => dataset})
      query = from(r in Resource, where: r.url == ^resource_url)
      assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
      assert query |> Repo.all() |> length() == 1
    end
  end
end
