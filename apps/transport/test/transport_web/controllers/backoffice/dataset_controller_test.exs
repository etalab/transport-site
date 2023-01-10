defmodule TransportWeb.Backoffice.DatasetControllerTest do
  use TransportWeb.ConnCase, async: true
  import Plug.Test
  alias TransportWeb.Router.Helpers, as: Routes
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  def setup_admin_in_session(conn) do
    conn
    |> init_test_session(%{
      current_user: %{
        "organizations" => [%{"slug" => "equipe-transport-data-gouv-fr"}]
      }
    })
  end

  test "update a dataset custom title", %{conn: conn} do
    dataset = insert(:dataset, custom_title: "title 1", slug: slug = "https://example.com/slug")

    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/slug/", _, _, _ ->
      {:ok, %HTTPoison.Response{body: "{\"id\": \"datagouv_id\"}", status_code: 200}}
    end)

    Transport.HTTPoison.Mock
    |> expect(:get!, fn "https://demo.data.gouv.fr/api/1/datasets/datagouv_id/", _, _ ->
      %HTTPoison.Response{body: "{\"id\": \"datagouv_id\", \"resources\": []}", status_code: 200}
    end)

    Datagouvfr.Client.CommunityResources.Mock
    |> expect(:get, fn _ -> {:ok, []} end)

    conn
    |> setup_admin_in_session()
    |> post(Routes.backoffice_dataset_path(conn, :post, dataset.id), %{
      "custom_title" => "new title",
      "url" => slug,
      "type" => "public-transit"
    })

    # the title has been updated, the dataset_id has not changed
    assert %{custom_title: "new title"} = DB.Repo.reload!(dataset)
  end

  test "update a dataset slug", %{conn: conn} do
    dataset =
      %{id: dataset_id} =
      insert(:dataset,
        datagouv_id: "datagouv_id",
        custom_title: "title",
        slug: "https://example.com/slug"
      )

    datagouv_id_2 = "datagouv_id_2"

    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/slug_2/", _, _, _ ->
      # the slug changes, the datagouv_id too
      {:ok, %HTTPoison.Response{body: "{\"id\": \"#{datagouv_id_2}\"}", status_code: 200}}
    end)

    slug_2 = "slug_2"

    Transport.HTTPoison.Mock
    |> expect(:get!, fn url, _, _ ->
      assert "https://demo.data.gouv.fr/api/1/datasets/#{datagouv_id_2}/" == url

      %HTTPoison.Response{
        body: "{\"id\": \"#{datagouv_id_2}\", \"resources\": [], \"slug\": \"#{slug_2}\"}",
        status_code: 200
      }
    end)

    Datagouvfr.Client.CommunityResources.Mock
    |> expect(:get, fn _ -> {:ok, []} end)

    conn
    |> setup_admin_in_session()
    |> post(Routes.backoffice_dataset_path(conn, :post, dataset.id), %{
      "custom_title" => "title",
      "url" => "https://example.com/#{slug_2}",
      "type" => "public-transit"
    })

    # the slug and datagouv_id have been updated, but the dataset_id has not changed
    assert %{id: ^dataset_id, datagouv_id: ^datagouv_id_2, custom_title: "title", slug: ^slug_2} =
             DB.Repo.reload!(dataset)
  end
end
