defmodule TransportWeb.EditDatasetLiveTest do
  use TransportWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Mox
  import DB.Factory

  setup :verify_on_exit!

  setup do
    # Using the real implementation for the moment, then it falls back on `HTTPoison.Mock`
    Mox.stub_with(Datagouvfr.Client.Datasets.Mock, Datagouvfr.Client.Datasets.External)
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "dataset form, input url is 404", %{conn: conn} do
    conn = conn |> setup_admin_in_session()

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.EditDatasetLive,
        session: %{
          "dataset" => nil,
          "dataset_types" => [],
          "regions" => [],
          "form_url" => "url_used_to_post_result"
        }
      )

    slug = "url_404"
    input_data_gouv_url = "http://data.gouv.fr/#{slug}"
    api_url = "https://demo.data.gouv.fr/api/1/datasets/#{slug}/"

    Transport.HTTPoison.Mock
    |> expect(:request, 1, fn :get, ^api_url, _, _, _ ->
      {:ok, %HTTPoison.Response{body: "", status_code: 404}}
    end)

    # this is done in the liveView by a spawned Task
    # but I couldn't find a way to use the Mox in the spawned process :(
    # so I do it manually
    datagouv_info = TransportWeb.EditDatasetLive.get_datagouv_infos(input_data_gouv_url)

    # the task sends back the message
    send(view.pid, {Process.monitor(self()), datagouv_info})

    assert render(view) =~ "Impossible de trouver ce jeu de données sur data.gouv"
  end

  test "dataset form, input url is 200, new dataset", %{conn: conn} do
    conn = conn |> setup_admin_in_session()

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.EditDatasetLive,
        session: %{
          "dataset" => nil,
          "dataset_types" => [],
          "regions" => [],
          "form_url" => "url_used_to_post_result"
        }
      )

    input_data_gouv_url = "http://data.gouv.fr/url_200"

    Transport.HTTPoison.Mock
    |> expect(:request, 1, fn :get, "https://demo.data.gouv.fr/api/1/datasets/url_200/", _, _, _ ->
      {:ok,
       %HTTPoison.Response{
         body: ~s({"id":"1234","title": "Horaires de Talence", "organization": {"name": "Mairie de Talence"}}),
         status_code: 200
       }}
    end)

    # this is shown only when we know the organization name
    refute render(view) =~ "publié par"

    datagouv_info = TransportWeb.EditDatasetLive.get_datagouv_infos(input_data_gouv_url)

    # the task sends back the message
    send(view.pid, {Process.monitor(self()), datagouv_info})

    assert render(view) =~ "Horaires de Talence"
    assert render(view) =~ "1234"
    assert render(view) =~ "pas encore référencé chez nous"

    assert render(view) =~ "publié par"
    assert render(view) =~ "Mairie de Talence"
  end

  test "dataset form, input url is 200, existing dataset", %{conn: conn} do
    conn = conn |> setup_admin_in_session()

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.EditDatasetLive,
        session: %{
          "dataset" => nil,
          "dataset_types" => [],
          "regions" => [],
          "form_url" => "url_used_to_post_result"
        }
      )

    insert(:dataset, datagouv_id: datagouv_id = "1234")

    input_data_gouv_url = "http://data.gouv.fr/url_200"

    Transport.HTTPoison.Mock
    |> expect(:request, 1, fn :get, "https://demo.data.gouv.fr/api/1/datasets/url_200/", _, _, _ ->
      {:ok,
       %HTTPoison.Response{
         body: ~s({"id":"#{datagouv_id}","title": "Horaires de Talence"}),
         status_code: 200
       }}
    end)

    datagouv_info = TransportWeb.EditDatasetLive.get_datagouv_infos(input_data_gouv_url)

    # the task sends back the message
    send(view.pid, {Process.monitor(self()), datagouv_info})

    assert render(view) =~ "Horaires de Talence"
    assert render(view) =~ "1234"
    assert render(view) =~ "Ce jeu de données est déjà référencé"
  end

  test "dataset form, show legal AOM owners saved in database", %{conn: conn} do
    conn = conn |> setup_admin_in_session()

    dataset =
      insert(:dataset,
        datagouv_id: "1234",
        legal_owners_aom: [insert(:aom, nom: aom_name = "Bordeaux Métropole")],
        legal_owners_region: [insert(:region, nom: region_name = "jolie région")]
      )

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.EditDatasetLive,
        session: %{
          "dataset" => dataset,
          "dataset_types" => [],
          "regions" => [],
          "form_url" => "url_used_to_post_result"
        }
      )

    assert render(view) =~ "Représentants légaux"
    assert render(view) =~ aom_name
    assert render(view) =~ region_name
  end

  test "dataset form, show legal company owner saved in database", %{conn: conn} do
    conn = conn |> setup_admin_in_session()

    dataset =
      insert(:dataset,
        datagouv_id: "1234",
        legal_owner_company_siren: siren = "552049447",
        legal_owners_aom: [],
        legal_owners_region: []
      )

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.EditDatasetLive,
        session: %{
          "dataset" => dataset,
          "dataset_types" => [],
          "regions" => [],
          "form_url" => "url_used_to_post_result"
        }
      )

    assert render(view) =~ "Représentants légaux"
    assert render(view) =~ siren
  end

  test "form inputs are persisted", %{conn: conn} do
    conn = conn |> setup_admin_in_session()
    aom = insert(:aom, nom: "mon AOM")

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.EditDatasetLive,
        session: %{
          "dataset" => nil,
          "dataset_types" => [],
          "regions" => [],
          "form_url" => "url_used_to_post_result"
        }
      )

    custom_title = "dataset custom title"

    # fill the custom title input, it should be rendered
    assert view
           |> element("form")
           |> render_change(%{_target: ["form", "custom_title"], form: %{custom_title: custom_title}}) =~ custom_title

    # add a legal owner, by sending a message
    send(view.pid, {:updated_legal_owner, [%{id: aom.id, label: aom.nom, type: "aom"}]})

    # the legal owner is rendered
    assert render(view) =~ aom.nom
    # custom title has not been cleared
    assert render(view) =~ custom_title
  end
end
