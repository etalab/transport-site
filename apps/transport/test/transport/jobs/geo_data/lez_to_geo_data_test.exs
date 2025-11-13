defmodule Transport.Jobs.LowEmissionZonesToGeoDataTest do
  # The trigger refresh_dataset_geographic_view_trigger makes this test
  # unreliable in a concurrent setup.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.{BaseGeoData, LowEmissionZonesToGeoData}
  import DB.Factory
  import Mox

  doctest LowEmissionZonesToGeoData, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  @lez_aires_content ~S"""
  {"features":[{"geometry":{"coordinates":[[[[102.0,2.0],[103.0,2.0],[103.0,3.0],[102.0,3.0],[102.0,2.0]]],[[[100.0,0.0],[101.0,0.0],[101.0,1.0],[100.0,1.0],[100.0,0.0]],[[100.2,0.2],[100.2,0.8],[100.8,0.8],[100.8,0.2],[100.2,0.2]]]],"type":"MultiPolygon"},"properties":{"autobus_autocars_critair":null,"autobus_autocars_horaires":null,"date_debut":"2010-01-01","date_fin":"2050-01-01","deux_rm_critair":null,"deux_rm_horaires":null,"id":"200040715-ZFE-001","pl_critair":"V3","pl_horaires":"24/7","url_arrete":"https://www.mobilites-m.fr/pdf/arrete_ZFE_VUL_PL.pdf","url_site":"https://www.grenoblealpesmetropole.fr/831-la-zfe.htm","vp_critair":null,"vp_horaires":null,"vul_critair":"V3","vul_horaires":"24/7"},"publisher":{"forme_juridique":"Syndicat mixte ouvert","nom":"Syndicat Mixte des Mobilités de l'Aire Grenobloise","siren":"253800825","zfe_id":"GRENOBLE"},"type":"Feature"}],"type":"FeatureCollection"}
  """

  test "import a ZFE to the DB" do
    geo_data_import = %{id: id} = insert(:geo_data_import)
    BaseGeoData.insert_data(@lez_aires_content, id, &LowEmissionZonesToGeoData.prepare_data_for_insert/2)

    [row1] = DB.GeoData |> DB.Repo.all()

    assert %{
             geo_data_import_id: ^id,
             geom: %Geo.MultiPolygon{
               coordinates: [
                 [[{102.0, 2.0}, {103.0, 2.0}, {103.0, 3.0}, {102.0, 3.0}, {102.0, 2.0}]],
                 [
                   [{100.0, +0.0}, {101.0, +0.0}, {101.0, 1.0}, {100.0, 1.0}, {100.0, +0.0}],
                   [{100.2, 0.2}, {100.2, 0.8}, {100.8, 0.8}, {100.8, 0.2}, {100.2, 0.2}]
                 ]
               ],
               srid: 4326
             },
             payload: %{
               "autobus_autocars_critair" => nil,
               "autobus_autocars_horaires" => nil,
               "date_debut" => "2010-01-01",
               "date_fin" => "2050-01-01",
               "deux_rm_critair" => nil,
               "deux_rm_horaires" => nil,
               "id" => "200040715-ZFE-001",
               "pl_critair" => "V3",
               "pl_horaires" => "24/7",
               "url_arrete" => "https://www.mobilites-m.fr/pdf/arrete_ZFE_VUL_PL.pdf",
               "url_site" => "https://www.grenoblealpesmetropole.fr/831-la-zfe.htm",
               "vp_critair" => nil,
               "vp_horaires" => nil,
               "vul_critair" => "V3",
               "vul_horaires" => "24/7"
             }
           } = row1

    # test cascading delete: if geo_data_import is deleted, associated geo_data are deleted too
    geo_data_import |> DB.Repo.delete!()
    assert [] = DB.GeoData |> DB.Repo.all()
  end

  test "ZFE data update logic" do
    now = DateTime.utc_now()
    now_100 = now |> DateTime.add(-100)
    now_50 = now |> DateTime.add(-50)
    now_25 = now |> DateTime.add(-25)

    assert [] = DB.GeoData |> DB.Repo.all()
    assert [] = DB.GeoDataImport |> DB.Repo.all()

    %DB.Dataset{id: dataset_id} = insert_zfe_dataset()

    %{id: resource_id} = insert(:resource, %{dataset_id: dataset_id, title: "aires.geojson", format: "geojson"})
    # these should be ignored
    insert(:resource, %{dataset_id: dataset_id, is_community_resource: true})
    insert(:resource, %{dataset_id: dataset_id, title: "voies.geojson", format: "geojson"})

    %{id: id_0} =
      insert(:resource_history, %{
        resource_id: resource_id,
        inserted_at: now_100,
        payload: %{"dataset_id" => dataset_id, "permanent_url" => "url"}
      })

    # another random resource history, just in case
    insert(:resource_history, %{inserted_at: now_25, payload: %{"dataset_id" => dataset_id + 5}})

    # download ZFE Mock
    Transport.HTTPoison.Mock
    |> expect(:get!, 2, fn "url" -> %HTTPoison.Response{status_code: 200, body: @lez_aires_content} end)

    # launch job
    assert :ok = perform_job(LowEmissionZonesToGeoData, %{})

    # data is imported
    [%DB.GeoDataImport{id: geo_data_import_1, resource_history_id: ^id_0, slug: :zfe}] =
      DB.GeoDataImport |> DB.Repo.all()

    assert DB.GeoData |> DB.Repo.all() |> Enum.count() == 1

    # relaunch job
    assert :ok = perform_job(LowEmissionZonesToGeoData, %{})

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
    assert :ok = perform_job(LowEmissionZonesToGeoData, %{})

    # geo_data and geo_data_import are updated accordingly
    [%DB.GeoDataImport{id: geo_data_import_2, resource_history_id: ^id_1, slug: :zfe}] =
      DB.GeoDataImport |> DB.Repo.all()

    assert geo_data_import_2 !== geo_data_import_1

    [%{geo_data_import_id: ^geo_data_import_2}] = DB.GeoData |> DB.Repo.all()
  end
end
