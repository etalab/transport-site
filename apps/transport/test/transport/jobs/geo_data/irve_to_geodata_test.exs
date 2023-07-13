defmodule Transport.Jobs.IRVEToGeoDataTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.{BaseGeoData, IRVEToGeoData}
  import DB.Factory
  import Mox

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  @irve_content ~S"""
  nom_amenageur,siren_amenageur,contact_amenageur,nom_operateur,contact_operateur,telephone_operateur,nom_enseigne,id_station_itinerance,id_station_local,nom_station,implantation_station,adresse_station,code_insee_commune,coordonneesXY,nbre_pdc,id_pdc_itinerance,id_pdc_local,puissance_nominale,prise_type_ef,prise_type_2,prise_type_combo_ccs,prise_type_chademo,prise_type_autre,gratuit,paiement_acte,paiement_cb,paiement_autre,tarification,condition_acces,reservation,horaires,accessibilite_pmr,restriction_gabarit,station_deux_roues,raccordement,num_pdl,date_mise_en_service,observations,date_maj,cable_t2_attache,last_modified,datagouv_dataset_id,datagouv_resource_id,datagouv_organization_or_owner,consolidated_longitude,consolidated_latitude,consolidated_code_postal,consolidated_commune,consolidated_is_lon_lat_correct,consolidated_is_code_insee_verified
  ,,info@example.com,,info@example.com,,STATION SUPER U BELLEVIGNY 4,FRCPIE6610355,FRCPIE6610355,STATION SUPER U BELLEVIGNY 4,Parking privé à usage public,"23 Av. Atlant’Vie, 85170 Bellevigny",,"[-1.429227, 46.776249]",6,FRCPIE66103552,FRCPIE66103552,21,false,true,false,false,false,false,true,false,,,Accès réservé,false,24/7,Accessibilité inconnue,inconnu,false,,,2022-10-12,EF connector is available at the site separately,2023-07-10,false,2023-07-11T03:08:58.394000+00:00,64060c2ac773dcf3fabbe5d2,b11113db-875d-41c7-8673-0cf8ad43e917,eco-movement,-1.429227,46.776249,,,False,False
  ,,info2@example.com,,info2@example.com,,Giberville Sud,FRIONE4171,FRIONE4171,Giberville Sud,Station dédiée à la recharge rapide,"Aire de Giberville Sud, A13, km 220, 14730 Giberville",,"[-0.276864, 49.166746]",5,FRIONE41715,FRIONE41715,50,false,true,true,true,false,false,true,true,,,Accès libre,false,24/7,Accessibilité inconnue,inconnu,false,,,2021-11-20,EF connector is available at the site separately,2023-07-11,false,2023-07-11T03:08:58.394000+00:00,64060c2ac773dcf3fabbe5d2,b11113db-875d-41c7-8673-0cf8ad43e917,eco-movement,-0.276864,49.166746,,,False,False
  """

  @dataset_info %{
    type: "charging-stations",
    custom_title: "Infrastructures de Recharge pour Véhicules Électriques - IRVE",
    organization: "Etalab",
    organization_id: "534fff75a3a7292c64a77de4"
  }

  test "import an IRVE to the DB" do
    %{id: id} = insert(:geo_data_import)
    BaseGeoData.insert_data(@irve_content, id, &IRVEToGeoData.prepare_data_for_insert/2)
    [row1 | _t] = DB.GeoData |> DB.Repo.all()

    assert %{
             geo_data_import_id: ^id,
             geom: %Geo.Point{
               coordinates: {-1.429227, 46.776249},
               srid: 4326
             },
             payload: %{
               "nom_enseigne" => "STATION SUPER U BELLEVIGNY 4",
               "nom_station" => "STATION SUPER U BELLEVIGNY 4",
               "id_station_itinerance" => "FRCPIE6610355",
               "nbre_pdc" => "6"
             }
           } = row1
  end

  test "Finds the relevant dataset" do
    %DB.Dataset{id: dataset_id} = insert(:dataset, @dataset_info)
    assert %DB.Dataset{id: ^dataset_id} = IRVEToGeoData.relevant_dataset()
  end

  test "IRVE data update logic" do
    now = DateTime.utc_now()
    now_100 = now |> DateTime.add(-100)
    now_50 = now |> DateTime.add(-50)
    now_25 = now |> DateTime.add(-25)

    assert [] = DB.GeoData |> DB.Repo.all()
    assert [] = DB.GeoDataImport |> DB.Repo.all()

    %DB.Dataset{id: dataset_id} = insert(:dataset, @dataset_info)

    # We don’t want to match community resources (but want to have them in base)
    insert(:resource, %{
      dataset_id: dataset_id,
      is_community_resource: true,
      datagouv_id: Ecto.UUID.generate()
    })

    %{id: resource_id} =
      insert(:resource, %{
        dataset_id: dataset_id,
        datagouv_id: "8d9398ae-3037-48b2-be19-412c24561fbb",
        format: "csv"
      })

    %{id: id_0} =
      insert(:resource_history, %{
        resource_id: resource_id,
        inserted_at: now_100,
        payload: %{"dataset_id" => dataset_id, "permanent_url" => "url"}
      })

    # another random resource history, just in case
    insert(:resource_history, %{inserted_at: now_25, payload: %{"dataset_id" => dataset_id + 5}})

    # download IRVE Mock
    Transport.HTTPoison.Mock
    |> expect(:get!, 2, fn "url" -> %HTTPoison.Response{status_code: 200, body: @irve_content} end)

    # launch job
    assert :ok = perform_job(IRVEToGeoData, %{})

    # data is imported
    [%{id: geo_data_import_1, resource_history_id: ^id_0}] = DB.GeoDataImport |> DB.Repo.all()
    assert DB.GeoData |> DB.Repo.all() |> Enum.count() == 2

    # relaunch job
    assert :ok = perform_job(IRVEToGeoData, %{})

    # no change
    [%{id: ^geo_data_import_1}] = DB.GeoDataImport |> DB.Repo.all()

    # new (more recent) resource history
    %{id: id_1} =
      insert(:resource_history, %{
        resource_id: resource_id,
        inserted_at: now_50,
        payload: %{"dataset_id" => dataset_id, "permanent_url" => "url"}
      })

    # relaunch job
    assert :ok = perform_job(IRVEToGeoData, %{})

    # geo_data and geo_data_import are updated accordingly
    [%{id: geo_data_import_2, resource_history_id: ^id_1}] = DB.GeoDataImport |> DB.Repo.all()
    assert geo_data_import_2 !== geo_data_import_1

    [%{geo_data_import_id: ^geo_data_import_2}, %{geo_data_import_id: ^geo_data_import_2}] = DB.GeoData |> DB.Repo.all()
  end
end
