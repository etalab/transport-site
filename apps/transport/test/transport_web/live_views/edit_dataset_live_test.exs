defmodule TransportWeb.EditDatasetLiveTest do
  use TransportWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Mox
  import DB.Factory

  setup :verify_on_exit!

  setup do
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
         body: ~s({"id":"1234","title": "Horaires de Talence"}),
         status_code: 200
       }}
    end)

    datagouv_info = TransportWeb.EditDatasetLive.get_datagouv_infos(input_data_gouv_url)

    # the task sends back the message
    send(view.pid, {Process.monitor(self()), datagouv_info})

    assert render(view) =~ "Horaires de Talence"
    assert render(view) =~ "1234"
    assert render(view) =~ "pas encore référencé chez nous"
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
end
