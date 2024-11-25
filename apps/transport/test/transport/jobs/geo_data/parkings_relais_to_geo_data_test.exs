defmodule Transport.Jobs.ParkingsRelaisToGeoDataTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.{BaseGeoData, ParkingsRelaisToGeoData}
  import DB.Factory
  import Mox

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  @parking_relais_content ~S"""
  id;nom;Xlong;Ylat;nb_pr
  04070-P-001;Parking Gassendi;6.2366534;44.0932836;
  04070-P-002;Parking Deux;6.22;44.10;5
  """

  test "import a Parking Relais to the DB" do
    geo_data_import = %{id: id} = insert(:geo_data_import)
    BaseGeoData.insert_data(@parking_relais_content, id, &ParkingsRelaisToGeoData.prepare_data_for_insert/2)

    [row1] = DB.GeoData |> DB.Repo.all()

    assert %{
             geo_data_import_id: ^id,
             geom: %Geo.Point{coordinates: {6.22, 44.1}, srid: 4326},
             payload: %{"nom" => "Parking Deux", "nb_pr" => "5"}
           } = row1

    # test cascading delete: if geo_data_import is deleted, associated geo_data are deleted too
    geo_data_import |> DB.Repo.delete!()
    assert [] = DB.GeoData |> DB.Repo.all()
  end

  test "Parking relais data update logic" do
    now = DateTime.utc_now()
    now_100 = now |> DateTime.add(-100)
    now_50 = now |> DateTime.add(-50)
    now_25 = now |> DateTime.add(-25)

    assert [] = DB.GeoData |> DB.Repo.all()
    assert [] = DB.GeoDataImport |> DB.Repo.all()

    %DB.Dataset{id: dataset_id} = insert_parcs_relais_dataset()

    insert(:resource, %{dataset_id: dataset_id, is_community_resource: true})
    %{id: resource_id} = insert(:resource, %{dataset_id: dataset_id, title: "parking-relais.csv", format: "csv"})

    %{id: id_0} =
      insert(:resource_history, %{
        resource_id: resource_id,
        inserted_at: now_100,
        payload: %{"dataset_id" => dataset_id, "permanent_url" => "url"}
      })

    # another random resource history, just in case
    insert(:resource_history, %{inserted_at: now_25, payload: %{"dataset_id" => dataset_id + 5}})

    # download Parking Relais Mock
    Transport.HTTPoison.Mock
    |> expect(:get!, 2, fn "url" -> %HTTPoison.Response{status_code: 200, body: @parking_relais_content} end)

    # launch job
    assert :ok = perform_job(ParkingsRelaisToGeoData, %{})

    # data is imported
    [%DB.GeoDataImport{id: geo_data_import_1, resource_history_id: ^id_0, slug: :parkings_relais}] =
      DB.GeoDataImport |> DB.Repo.all()

    assert DB.GeoData |> DB.Repo.all() |> Enum.count() == 1

    # relaunch job
    assert :ok = perform_job(ParkingsRelaisToGeoData, %{})

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
    assert :ok = perform_job(ParkingsRelaisToGeoData, %{})

    # geo_data and geo_data_import are updated accordingly
    [%DB.GeoDataImport{id: geo_data_import_2, resource_history_id: ^id_1, slug: :parkings_relais}] =
      DB.GeoDataImport |> DB.Repo.all()

    assert geo_data_import_2 !== geo_data_import_1

    [%{geo_data_import_id: ^geo_data_import_2}] = DB.GeoData |> DB.Repo.all()
  end
end
