defmodule Transport.Jobs.BNLCToGeoDataTest do
  use ExUnit.Case, async: true
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

  test "import an IRVE to the DB" do
    %{id: id} = insert(:geo_data_import)
    # Uncomment to test only the prepare_data_for_insert function
    # row1 = IRVEToGeoData.prepare_data_for_insert(@irve_content, id) |> Enum.take(1) |> hd
    BaseGeoData.insert_data(@irve_content, id, &IRVEToGeoData.prepare_data_for_insert/2)
    [row1| _t] = DB.GeoData |> DB.Repo.all()

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
end