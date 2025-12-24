defmodule TransportWeb.AOMsControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory

  setup do
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)
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
             has_realtime: false,
             nb_gtfs: 0
           } = TransportWeb.AOMSController.aoms() |> Enum.find(fn r -> r.nom == aom.nom end)
  end

  test "display AOM information using legal owners" do
    %DB.AOM{nom: nom_aom} = aom = insert(:aom, nom: "Super AOM 76")
    aom2 = insert(:aom)

    dataset =
      insert(:dataset,
        legal_owners_aom: [aom, aom2],
        is_active: true,
        type: "public-transit",
        has_realtime: true
      )

    insert(:resource, format: "NeTEx", dataset: dataset)

    DB.Factory.insert_resource_and_friends(Date.utc_today() |> Date.add(10), dataset: dataset)

    assert %{
             nom: ^nom_aom,
             published: true,
             in_aggregate: true,
             up_to_date: true,
             has_realtime: true,
             nb_gtfs: 1,
             nb_netex: 1
           } = TransportWeb.AOMSController.aoms() |> Enum.find(fn r -> r.nom == aom.nom end)
  end

  test "Having an aggregated dataset without GTFS associated validations works" do
    %DB.AOM{nom: nom_aom} = aom = insert(:aom, nom: "Super AOM 76")
    aom2 = insert(:aom)

    dataset =
      insert(:dataset,
        legal_owners_aom: [aom, aom2],
        is_active: true,
        type: "public-transit",
        has_realtime: true
      )

    insert(:resource, title: "GTFS-flex TAD", dataset: dataset, format: "GTFS")
    insert(:resource, dataset: dataset, format: "gtfs-rt")

    assert %{
             nom: ^nom_aom,
             published: true,
             in_aggregate: true,
             # The controller only gets up to date information for GTFS datasets
             up_to_date: false,
             # This is a quirk that could be corrected with some effort
             has_realtime: false,
             nb_gtfs: 1,
             nb_gtfs_rt: 1
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
             has_realtime: true,
             nb_gtfs: 2
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
             has_realtime: true,
             nb_gtfs: 1
           } = TransportWeb.AOMSController.aoms() |> Enum.find(fn r -> r.nom == aom.nom end)
  end

  test "displays AOM information without dataset" do
    %DB.AOM{nom: nom_aom} = aom = insert(:aom, nom: "Super AOM 76")

    assert %{
             nom: ^nom_aom,
             published: false,
             in_aggregate: false,
             up_to_date: false,
             has_realtime: false,
             nb_gtfs: 0
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

  test "can download the CSV", %{conn: conn} do
    departement = insert(:departement, insee: "76")
    commune = insert(:commune, nom: "Rouen", insee: "76540", departement_insee: departement.insee)

    aom =
      insert(:aom,
        nom: "Seine-Maritime",
        region: region = insert(:region, nom: "Normandie"),
        insee_commune_principale: commune.insee,
        departement_object: departement,
        nombre_communes: 1
      )

    dataset = insert(:dataset, legal_owners_aom: [aom], is_active: true, type: "public-transit", has_realtime: true)

    DB.Factory.insert_resource_and_friends(Date.utc_today() |> Date.add(10), dataset: dataset)

    assert [
             %{
               "departement" => departement.insee,
               "has_realtime" => "true",
               "in_aggregate" => "false",
               "insee_commune_principale" => aom.insee_commune_principale,
               "nb_gtfs" => "1",
               "nb_gtfs_rt" => "0",
               "nb_netex" => "0",
               "nb_siri" => "0",
               "nb_siri_lite" => "0",
               "nom" => aom.nom,
               "nom_commune" => commune.nom,
               "nombre_communes" => aom.nombre_communes |> to_string(),
               "population" => aom.population |> to_string(),
               "published" => "true",
               "region" => region.nom,
               "up_to_date" => "true"
             }
           ] == [conn |> get(aoms_path(conn, :csv)) |> response(200)] |> CSV.decode!(headers: true) |> Enum.to_list()
  end
end
