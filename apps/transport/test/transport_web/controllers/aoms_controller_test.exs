defmodule TransportWeb.AOMsControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "display AOM information with inactive dataset" do
    aom = insert(:aom, nom: "aom")
    insert(:dataset, is_active: false, legal_owners_aom: [aom], has_realtime: true, type: "public-transit")

    assert %{
             nom: "aom",
             published: false,
             in_aggregate: false,
             up_to_date: false,
             has_realtime: false
           } = TransportWeb.AOMSController.aoms() |> Enum.find(fn r -> r.nom == aom.nom end)
  end

  test "display AOM information using legal owners" do
    %DB.AOM{nom: nom_aom} = aom = insert(:aom, nom: "Super AOM 76")
    aom2 = insert(:aom)

    dataset =
      insert(:dataset,
        aom: nil,
        legal_owners_aom: [aom, aom2],
        is_active: true,
        type: "public-transit",
        has_realtime: true
      )

    assert is_nil(dataset.aom_id)

    DB.Factory.insert_resource_and_friends(Date.utc_today() |> Date.add(10), dataset: dataset)

    assert %{
             nom: ^nom_aom,
             published: true,
             in_aggregate: true,
             up_to_date: true,
             has_realtime: true
           } = TransportWeb.AOMSController.aoms() |> Enum.find(fn r -> r.nom == aom.nom end)
  end

  test "Having an aggregated dataset without GTFS associated validations works" do
    %DB.AOM{nom: nom_aom} = aom = insert(:aom, nom: "Super AOM 76")
    aom2 = insert(:aom)

    dataset =
      insert(:dataset,
        aom: nil,
        legal_owners_aom: [aom, aom2],
        is_active: true,
        type: "public-transit",
        has_realtime: true
      )

    assert is_nil(dataset.aom_id)

    insert(:resource, title: "GTFS-flex TAD", dataset: dataset, format: "GTFS")

    assert %{
             nom: ^nom_aom,
             published: true,
             in_aggregate: true,
             # The controller only gets up to date information for GTFS datasets
             up_to_date: false,
             # This is a quirk that could be corrected with some effort
             has_realtime: false
           } = TransportWeb.AOMSController.aoms() |> Enum.find(fn r -> r.nom == aom.nom end)
  end

  test "displays AOM information with datasets" do
    aom = insert(:aom, nom: "aom")
    dataset = insert(:dataset, legal_owners_aom: [aom], is_active: true, type: "public-transit", has_realtime: true)

    DB.Factory.insert_resource_and_friends(Date.utc_today() |> Date.add(-10), dataset: dataset)
    DB.Factory.insert_resource_and_friends(Date.utc_today() |> Date.add(10), dataset: dataset)

    assert %{
             nom: "aom",
             published: true,
             in_aggregate: false,
             up_to_date: true,
             has_realtime: true
           } = TransportWeb.AOMSController.aoms() |> Enum.find(fn r -> r.nom == aom.nom end)
  end

  test "displays AOM information with legal owners" do
    %DB.AOM{nom: nom_aom} = aom = insert(:aom, nom: "Super AOM 76")
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

  test "displays AOM information without dataset" do
    %DB.AOM{nom: nom_aom} = aom = insert(:aom, nom: "Super AOM 76")

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
      type: "public-transit"
    )

    assert conn |> get(aoms_path(conn, :index)) |> html_response(200) =~ aom.nom
  end
end
