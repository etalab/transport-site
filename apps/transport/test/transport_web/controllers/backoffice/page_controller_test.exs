defmodule TransportWeb.Backoffice.PageControllerTest do
  use ExUnit.Case
  alias TransportWeb.Backoffice.PageController
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
end
