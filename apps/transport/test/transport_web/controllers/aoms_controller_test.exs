defmodule TransportWeb.AomsControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "display AOM information with inactive dataset" do
    aom_1 = insert(:aom, nom: "aom_1")
    insert(:dataset, is_active: false, aom: aom_1, has_realtime: true, type: "public-transit")

    [aom] = TransportWeb.AOMSController.aoms()

    assert %{
             nom: "aom_1",
             published: false,
             in_aggregate: false,
             up_to_date: false,
             has_realtime: false
           } = aom
  end

  test "display AOM information with parent_dataset" do
    %{dataset: dataset} =
      DB.Factory.insert_resource_and_friends(Date.utc_today() |> Date.add(10),
        has_realtime: true,
        type: "public-transit"
      )

    aom = insert(:aom, nom: "aom", parent_dataset: dataset)
    aoms = TransportWeb.AOMSController.aoms()

    aom = aoms |> Enum.find(fn r -> r.nom == aom.nom end)

    assert %{
             nom: "aom",
             published: true,
             in_aggregate: true,
             up_to_date: true,
             has_realtime: true
           } = aom
  end

  test "displays AOM information with datasets" do
    aom = insert(:aom, nom: "aom")
    # insert 2 datasets, one is outdated
    %{dataset: dataset} =
      DB.Factory.insert_resource_and_friends(Date.utc_today() |> Date.add(-10),
        has_realtime: true,
        type: "public-transit",
        aom: aom
      )

    DB.Factory.insert_resource_and_friends(Date.utc_today() |> Date.add(10),
      dataset: dataset,
      has_realtime: false,
      type: "public-transit",
      aom: aom
    )

    aoms = TransportWeb.AOMSController.aoms()

    aom = aoms |> Enum.find(fn r -> r.nom == aom.nom end)

    assert %{
             nom: "aom",
             published: true,
             in_aggregate: false,
             up_to_date: true,
             has_realtime: true
           } = aom
  end

  test "displays AOM information with both parent_dataset and datasets" do
    %{dataset: parent_dataset} =
      DB.Factory.insert_resource_and_friends(Date.utc_today() |> Date.add(10),
        has_realtime: false,
        type: "public-transit"
      )

    aom = insert(:aom, nom: "aom", parent_dataset: parent_dataset)

    DB.Factory.insert_resource_and_friends(Date.utc_today() |> Date.add(-10),
      has_realtime: true,
      type: "public-transit",
      aom: aom
    )

    aoms = TransportWeb.AOMSController.aoms()
    aom = aoms |> Enum.find(fn r -> r.nom == aom.nom end)

    assert %{
             nom: "aom",
             published: true,
             in_aggregate: true,
             up_to_date: true,
             has_realtime: true
           } = aom
  end

  test "the page renders", %{conn: conn} do
    aom = insert(:aom, nom: "ma petite aom")

    DB.Factory.insert_resource_and_friends(Date.utc_today() |> Date.add(-10),
      has_realtime: true,
      type: "public-transit",
      aom: aom
    )

    res = conn |> get(aoms_path(conn, :index)) |> html_response(200)
    assert res =~ "ma petite aom"
  end
end
