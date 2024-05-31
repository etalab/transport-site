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
  nom_amenageur,siren_amenageur,contact_amenageur,nom_operateur,contact_operateur,telephone_operateur,nom_enseigne,id_station_itinerance,id_station_local,nom_station,implantation_station,adresse_station,code_insee_commune,coordonneesXY,nbre_pdc,id_pdc_itinerance,id_pdc_local,puissance_nominale,prise_type_ef,prise_type_2,prise_type_combo_ccs,prise_type_chademo,prise_type_autre,gratuit,paiement_acte,paiement_cb,paiement_autre,tarification,condition_acces,reservation,horaires,accessibilite_pmr,restriction_gabarit,station_deux_roues,raccordement,num_pdl,date_mise_en_service,observations,date_maj,cable_t2_attache,last_modified,datagouv_dataset_id,datagouv_resource_id,datagouv_organization_or_owner,created_at,consolidated_longitude,consolidated_latitude,consolidated_code_postal,consolidated_commune,consolidated_is_lon_lat_correct,consolidated_is_code_insee_verified
  ,,info@chargepoint.com,,info@chargepoint.com,,STATION SUPER U BELLEVIGNY 4,FRCPIE6610355,FRCPIE6610355,STATION SUPER U BELLEVIGNY 4,Voirie,"23 Av. Atlant’Vie, 85170 Bellevigny",,"[-1.429227, 46.776249]",6,FRCPIE66103552,FRCPIE66103552,0,false,true,false,false,false,false,true,false,,,Accès réservé,false,24/7,Accessibilité inconnue,inconnu,false,,,2022-10-12,EF connector is available at the site separately,2024-04-07,false,2024-04-08T01:00:12.115000+00:00,64060c2ac773dcf3fabbe5d2,b11113db-875d-41c7-8673-0cf8ad43e917,eco-movement,2023-06-28T11:46:08.539000+00:00,-1.429227,46.776249,,,False,False
  ,,info@ionity.eu,IONITY,info@ionity.eu,33187210891,IONITY GMBH,FRIONE417100,FRIONE417100,IONITY Giberville Sud,Station dédiée à la recharge rapide,"Aire de Giberville Sud, Km 220, A13, 14730 Giberville",14301,"[-0.277238, 49.166932]",5,FRIONE4171,FRIONE4171,350,FALSE,TRUE,TRUE,TRUE,FALSE,FALSE,TRUE,FALSE,TRUE,0.69€ / kwh,Accès libre,FALSE,24/7,Accessible mais non réservé PMR,Hauteur maximale 3m,FALSE,Direct,50017455185930,2021-11-18,Recharge jusqu'à 350KW - CCS,2023-03-21,TRUE,2024-01-19T07:47:22.735000+00:00,5b597823c751df57045198a4,78356665-f3f2-4588-aca0-a5cb1606d86d,ionity-gmbh,2023-03-30T14:20:56.532000+00:00,-0.277238,49.166932,14730,Giberville,True,True
  """

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

  test "IRVE data update logic" do
    now = DateTime.utc_now()
    now_200 = now |> DateTime.add(-200)
    now_100 = now |> DateTime.add(-100)
    now_50 = now |> DateTime.add(-50)
    now_25 = now |> DateTime.add(-25)

    assert [] = DB.GeoData |> DB.Repo.all()
    assert [] = DB.GeoDataImport |> DB.Repo.all()

    %DB.Dataset{id: dataset_id} = insert_irve_dataset()

    # We don’t want to match community resources (but want to have them in base)
    insert(:resource, %{
      dataset_id: dataset_id,
      is_community_resource: true,
      datagouv_id: Ecto.UUID.generate()
    })

    # 2.2.0
    %{id: old_resource_id} =
      insert(:resource, %{
        dataset_id: dataset_id,
        datagouv_id: "8d9398ae-3037-48b2-be19-412c24561fbb",
        format: "csv"
      })

    insert(:resource_history, %{
      resource_id: old_resource_id,
      inserted_at: now_200,
      payload: %{"dataset_id" => dataset_id, "permanent_url" => "url_2_2_0"}
    })

    # 2.3.1
    %{id: resource_id} =
      insert(:resource, %{
        dataset_id: dataset_id,
        datagouv_id: "eb76d20a-8501-400e-b336-d85724de5435",
        format: "csv"
      })

    %{id: id_1} =
      insert(:resource_history, %{
        resource_id: resource_id,
        inserted_at: now_100,
        payload: %{"dataset_id" => dataset_id, "permanent_url" => "url_2_3_1"}
      })

    # another random resource history, just in case
    insert(:resource_history, %{inserted_at: now_25, payload: %{"dataset_id" => dataset_id + 5}})

    # download IRVE Mock
    Transport.HTTPoison.Mock
    |> expect(:get!, 2, fn "url_2_3_1" -> %HTTPoison.Response{status_code: 200, body: @irve_content} end)

    # launch job
    assert :ok = perform_job(IRVEToGeoData, %{})

    # data is imported
    [%{id: geo_data_import_1, resource_history_id: ^id_1}] = DB.GeoDataImport |> DB.Repo.all()
    assert DB.GeoData |> DB.Repo.all() |> Enum.count() == 2

    # relaunch job
    assert :ok = perform_job(IRVEToGeoData, %{})

    # no change
    [%{id: ^geo_data_import_1}] = DB.GeoDataImport |> DB.Repo.all()

    # new (more recent) resource history
    %{id: id_2} =
      insert(:resource_history, %{
        resource_id: resource_id,
        inserted_at: now_50,
        payload: %{"dataset_id" => dataset_id, "permanent_url" => "url_2_3_1"}
      })

    # relaunch job
    assert :ok = perform_job(IRVEToGeoData, %{})

    # geo_data and geo_data_import are updated accordingly
    [%{id: geo_data_import_2, resource_history_id: ^id_2}] = DB.GeoDataImport |> DB.Repo.all()
    assert geo_data_import_2 !== geo_data_import_1

    [%{geo_data_import_id: ^geo_data_import_2}, %{geo_data_import_id: ^geo_data_import_2}] = DB.GeoData |> DB.Repo.all()
  end
end
