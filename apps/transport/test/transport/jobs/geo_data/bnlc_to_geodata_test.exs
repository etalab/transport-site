defmodule Transport.Jobs.BNLCToGeoDataTest do
  use ExUnit.Case
  alias Transport.Jobs.BNLCToGeoData
  import DB.Factory
  import Mox

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  @bnlc_content ~s("id_lieu","Xlong","Ylat","nbre_pl"\n"2A004-C-001","8.783403","41.9523692","0"\n"01024-C-001","5.158352778","46.28957222","5")

  test "import a BNLC to the DB" do
    geo_data_import = %{id: id} = insert(:geo_data_import, %{publish: true})
    BNLCToGeoData.insert_bnlc_data(@bnlc_content, id)

    [row1, row2] = DB.GeoData |> DB.Repo.all()

    assert %{
             geo_data_import_id: ^id,
             geom: %Geo.Point{coordinates: {8.783403, 41.9523692}, srid: 4326},
             payload: %{"id_lieu" => "2A004-C-001", "nbre_pl" => "0"}
           } = row1

    assert %{
             geo_data_import_id: ^id,
             geom: %Geo.Point{coordinates: {5.158352778, 46.28957222}, srid: 4326},
             payload: %{"id_lieu" => "01024-C-001", "nbre_pl" => "5"}
           } = row2

    # test cascading delete: if geo_data_import is deleted, associated geo_data are deleted too
    geo_data_import |> DB.Repo.delete!()
    assert [] = DB.GeoData |> DB.Repo.all()
  end

  test "bnlc data update logic" do
    dataset_id = 253
    now = DateTime.utc_now()
    now_100 = now |> DateTime.add(-100)
    now_50 = now |> DateTime.add(-50)
    now_25 = now |> DateTime.add(-25)

    assert [] = DB.GeoData |> DB.Repo.all()
    assert [] = DB.GeoDataImport |> DB.Repo.all()

    # insert bnlc dataset
    insert(:dataset, %{
      id: dataset_id,
      type: "carpooling-areas",
      organization: Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)
    })

    # insert bnlc resource
    insert(:resource, %{dataset_id: dataset_id, datagouv_id: resource_datagouv_id = "resource_datagouv_id"})
    # insert bnlc resource history
    %{id: id_0} =
      insert(:resource_history, %{
        datagouv_id: resource_datagouv_id,
        inserted_at: now_100,
        payload: %{"dataset_id" => dataset_id, "permanent_url" => "url"}
      })

    # another random resource history, just in case
    insert(:resource_history, %{inserted_at: now_25, payload: %{"dataset_id" => 99}})

    # download BNLC Mock
    Transport.HTTPoison.Mock
    |> expect(:get!, 2, fn "url" -> %HTTPoison.Response{status_code: 200, body: @bnlc_content} end)

    # launch job
    Transport.Jobs.BNLCToGeoData.perform(%{})

    # data is imported
    [%{id: geo_data_import_1, resource_history_id: ^id_0}] = DB.GeoDataImport |> DB.Repo.all()
    assert DB.GeoData |> DB.Repo.all() |> Enum.count() == 2

    # relaunch job
    Transport.Jobs.BNLCToGeoData.perform(%{})

    # no change
    [%{id: ^geo_data_import_1}] = DB.GeoDataImport |> DB.Repo.all()

    # new (more recent) resource history
    %{id: id_1} =
      insert(:resource_history, %{
        datagouv_id: resource_datagouv_id,
        inserted_at: now_50,
        payload: %{"dataset_id" => dataset_id, "permanent_url" => "url"}
      })

    # relaunch job
    Transport.Jobs.BNLCToGeoData.perform(%{})

    # geo_data and geo_data_import are updated accordingly
    [%{id: geo_data_import_2, resource_history_id: ^id_1}] = DB.GeoDataImport |> DB.Repo.all()
    assert geo_data_import_2 !== geo_data_import_1

    [%{geo_data_import_id: ^geo_data_import_2}, %{geo_data_import_id: ^geo_data_import_2}] = DB.GeoData |> DB.Repo.all()
  end
end
