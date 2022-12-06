defmodule TransportWeb.Backoffice.BrokenUrlsControllerTest do
  use TransportWeb.ConnCase, async: true
  import Plug.Test
  import DB.Factory
  alias TransportWeb.Backoffice.BrokenUrlsController

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "detect a broken url", %{conn: conn} do
    dataset = insert(:dataset)

    dataset_history = insert(:dataset_history, dataset_id: dataset.id)
    insert(:dataset_history_resources, dataset_history_id: dataset_history.id, payload: %{"download_url" => "url1"})
    dataset_history_2 = insert(:dataset_history, dataset_id: dataset.id)
    insert(:dataset_history_resources, dataset_history_id: dataset_history_2.id, payload: %{"download_url" => "url2"})

    conn =
      conn
      |> init_test_session(%{
        current_user: %{"organizations" => [%{"slug" => "equipe-transport-data-gouv-fr"}]}
      })
      |> get(backoffice_broken_urls_path(conn, :index))

    res = conn |> html_response(200)
    assert res =~ "Détection de changements d'urls stables"
    assert res =~ "/datasets/#{dataset.id}"
    assert res =~ "url1"
    assert res =~ "url2"
  end

  test "detect multiple broken urls" do
    dataset = insert(:dataset)
    dataset_history = insert(:dataset_history, dataset_id: dataset.id)
    insert(:dataset_history_resources, dataset_history_id: dataset_history.id, payload: %{"download_url" => "url1"})
    dataset_history_2 = insert(:dataset_history, dataset_id: dataset.id)
    insert(:dataset_history_resources, dataset_history_id: dataset_history_2.id, payload: %{"download_url" => "url2"})

    dataset_2 = insert(:dataset)
    dataset_history_3 = insert(:dataset_history, dataset_id: dataset_2.id)
    insert(:dataset_history_resources, dataset_history_id: dataset_history_3.id, payload: %{"download_url" => "url3"})
    dataset_history_4 = insert(:dataset_history, dataset_id: dataset_2.id)
    insert(:dataset_history_resources, dataset_history_id: dataset_history_4.id, payload: %{"download_url" => "url4"})
    insert(:dataset_history_resources, dataset_history_id: dataset_history_4.id, payload: %{"download_url" => "url5"})

    [broken_1, broken_2] = BrokenUrlsController.broken_urls()

    # we show recent events first => dataset_2 comes first
    assert %{
             dataset_id: dataset_2.id,
             inserted_at: dataset_history_4.inserted_at,
             urls: ["url4", "url5"],
             previous_urls: ["url3"],
             disappeared_urls: true,
             new_urls: true
           } == broken_1

    assert %{
             dataset_id: dataset.id,
             inserted_at: dataset_history_2.inserted_at,
             urls: ["url2"],
             previous_urls: ["url1"],
             disappeared_urls: true,
             new_urls: true
           } == broken_2
  end

  test "don't detect an unchanged url", %{conn: conn} do
    dataset = insert(:dataset)

    dataset_history = insert(:dataset_history, dataset_id: dataset.id)
    insert(:dataset_history_resources, dataset_history_id: dataset_history.id, payload: %{"download_url" => "url1"})
    dataset_history_2 = insert(:dataset_history, dataset_id: dataset.id)
    insert(:dataset_history_resources, dataset_history_id: dataset_history_2.id, payload: %{"download_url" => "url1"})

    conn =
      conn
      |> init_test_session(%{
        current_user: %{"organizations" => [%{"slug" => "equipe-transport-data-gouv-fr"}]}
      })
      |> get(backoffice_broken_urls_path(conn, :index))

    # check we get a 200 if list is empty
    res = conn |> html_response(200)
    refute res =~ "/datasets/#{dataset.id}"
  end

  test "don't detect just a new url" do
    dataset = insert(:dataset)

    dataset_history = insert(:dataset_history, dataset_id: dataset.id)
    insert(:dataset_history_resources, dataset_history_id: dataset_history.id, payload: %{"download_url" => "url1"})
    dataset_history_2 = insert(:dataset_history, dataset_id: dataset.id)
    insert(:dataset_history_resources, dataset_history_id: dataset_history_2.id, payload: %{"download_url" => "url1"})
    insert(:dataset_history_resources, dataset_history_id: dataset_history_2.id, payload: %{"download_url" => "url2"})

    assert [] == BrokenUrlsController.broken_urls()
  end

  test "don't detect just a deleted url" do
    dataset = insert(:dataset)

    dataset_history = insert(:dataset_history, dataset_id: dataset.id)
    insert(:dataset_history_resources, dataset_history_id: dataset_history.id, payload: %{"download_url" => "url1"})
    insert(:dataset_history_resources, dataset_history_id: dataset_history.id, payload: %{"download_url" => "url2"})
    dataset_history_2 = insert(:dataset_history, dataset_id: dataset.id)
    insert(:dataset_history_resources, dataset_history_id: dataset_history_2.id, payload: %{"download_url" => "url1"})

    assert [] == BrokenUrlsController.broken_urls()
  end
end
