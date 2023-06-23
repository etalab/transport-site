defmodule TransportWeb.AOMsControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
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

  test "display AOM information using legal owners" do
    %DB.AOM{nom: nom_aom} = aom = insert(:aom)
    aom2 = insert(:aom)

    dataset =
      insert(:dataset, legal_owners_aom: [aom, aom2], is_active: true, type: "public-transit", has_realtime: true)

    DB.Factory.insert_resource_and_friends(Date.utc_today() |> Date.add(10), dataset: dataset)

    assert %{
             nom: ^nom_aom,
             published: true,
             in_aggregate: true,
             up_to_date: true,
             has_realtime: true
           } = TransportWeb.AOMSController.aoms() |> Enum.find(fn r -> r.nom == aom.nom end)
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

    assert %{
             nom: "aom",
             published: true,
             in_aggregate: false,
             up_to_date: true,
             has_realtime: true
           } = TransportWeb.AOMSController.aoms() |> Enum.find(fn r -> r.nom == aom.nom end)
  end

  test "displays AOM information with both legal owners and datasets" do
    %DB.AOM{nom: nom_aom} = aom = insert(:aom)
    aom2 = insert(:aom)

    dataset =
      insert(:dataset, legal_owners_aom: [aom, aom2], is_active: true, type: "public-transit", has_realtime: false)

    DB.Factory.insert_resource_and_friends(Date.utc_today() |> Date.add(10), dataset: dataset)

    DB.Factory.insert_resource_and_friends(Date.utc_today() |> Date.add(-10),
      has_realtime: true,
      type: "public-transit",
      aom: aom
    )

    assert %{
             nom: ^nom_aom,
             published: true,
             in_aggregate: true,
             up_to_date: true,
             has_realtime: true
           } = TransportWeb.AOMSController.aoms() |> Enum.find(fn r -> r.nom == aom.nom end)
  end

  test "displays AOM information without dataset" do
    %DB.AOM{nom: nom_aom} = aom = insert(:aom)

    assert %{
             nom: ^nom_aom,
             published: false,
             in_aggregate: false,
             up_to_date: false,
             has_realtime: false
           } = TransportWeb.AOMSController.aoms() |> Enum.find(fn r -> r.nom == aom.nom end)
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
