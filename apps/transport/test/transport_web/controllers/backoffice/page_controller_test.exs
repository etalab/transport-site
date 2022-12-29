defmodule TransportWeb.Backoffice.PageControllerTest do
  use TransportWeb.ConnCase, async: true
  import Plug.Test, only: [init_test_session: 2]
  alias TransportWeb.Backoffice.PageController
  alias TransportWeb.Router.Helpers, as: Routes
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "check availability filter" do
    now = DateTime.utc_now()
    # 10% downtime of 30 days is 72 hours
    hours_ago_73 = now |> DateTime.add(-73 * 60 * 60)
    minute_ago_1 = now |> DateTime.add(-60)

    # dataset 1 : resource always available
    %{id: dataset_id_1} = insert(:dataset)
    insert(:resource, %{dataset_id: dataset_id_1})

    # dataset 2 : 1 resource unavailable
    %{id: dataset_id_2} = insert(:dataset)

    %{id: resource_id_2_1} = insert(:resource, %{dataset_id: dataset_id_2})
    insert(:resource, %{dataset_id: dataset_id_2})

    insert(:resource_unavailability, %{resource_id: resource_id_2_1, start: hours_ago_73, end: minute_ago_1})

    # dataset 3 : all resources unavailable
    %{id: dataset_id_3} = insert(:dataset)

    %{id: resource_id_3_1} = insert(:resource, %{dataset_id: dataset_id_3})
    %{id: resource_id_3_2} = insert(:resource, %{dataset_id: dataset_id_3})

    insert(:resource_unavailability, %{resource_id: resource_id_3_1, start: hours_ago_73, end: minute_ago_1})
    insert(:resource_unavailability, %{resource_id: resource_id_3_2, start: hours_ago_73})

    assert [dataset_id_2, dataset_id_3] == PageController.dataset_with_resource_under_90_availability()
  end

  test "inactive datasets are filtered out" do
    now = DateTime.utc_now()
    hours_ago_73 = now |> DateTime.add(-73 * 60 * 60)
    minute_ago_1 = now |> DateTime.add(-60)

    %{id: dataset_id} = insert(:dataset, %{is_active: false})
    %{id: resource_id} = insert(:resource, %{dataset_id: dataset_id})
    insert(:resource_unavailability, %{resource_id: resource_id, start: hours_ago_73, end: minute_ago_1})

    assert [] == PageController.dataset_with_resource_under_90_availability()
  end

  test "outdated datasets filter", %{conn: conn} do
    insert_outdated_resource_and_friends(custom_title: "un dataset outdated")
    insert_up_to_date_resource_and_friends(custom_title: "un dataset bien à jour")

    conn1 =
      conn
      |> init_test_session(%{
        current_user: %{"organizations" => [%{"slug" => "blurp"}, %{"slug" => "equipe-transport-data-gouv-fr"}]}
      })
      |> get(Routes.backoffice_page_path(conn, :index))

    assert html_response(conn1, 200) =~ "un dataset outdated"
    assert html_response(conn1, 200) =~ "un dataset bien à jour"

    conn2 =
      conn
      |> init_test_session(%{
        current_user: %{"organizations" => [%{"slug" => "blurp"}, %{"slug" => "equipe-transport-data-gouv-fr"}]}
      })
      |> get(
        Routes.backoffice_page_path(conn, :index, %{"filter" => "outdated", "dir" => "asc", "order_by" => "end_date"})
      )

    assert html_response(conn2, 200) =~ "un dataset outdated"
    refute html_response(conn2, 200) =~ "un dataset bien à jour"
  end
end
