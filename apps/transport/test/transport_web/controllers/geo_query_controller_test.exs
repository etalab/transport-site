defmodule TransportWeb.API.GeoQueryControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "a bnlc geo query", %{conn: conn} do
    transport_publisher_label = Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)

    %{id: dataset_id} = insert(:dataset, %{type: "carpooling-areas", organization: transport_publisher_label})
    %{id: resource_history_id} = insert(:resource_history, %{payload: %{"dataset_id" => dataset_id}})
    %{id: geo_data_import_id} = insert(:geo_data_import, %{resource_history_id: resource_history_id})

    %{id: geo_data_import_id_ko} = insert(:geo_data_import)

    point1 = %Geo.Point{coordinates: {1, 1}, srid: 4326}
    point2 = %Geo.Point{coordinates: {2, 2}, srid: 4326}

    insert(:geo_data, %{geo_data_import_id: geo_data_import_id, geom: point1, payload: %{"nom_lieu" => "Ajaccio"}})

    insert(:geo_data, %{geo_data_import_id: geo_data_import_id, geom: point2, payload: %{"nom_lieu" => "Coti-Chiavari"}})

    insert(:geo_data, %{geo_data_import_id: geo_data_import_id_ko, geom: point2, payload: %{"nom_lieu" => "Bastia"}})

    path = TransportWeb.API.Router.Helpers.geo_query_path(conn, :index, data: "bnlc")
    conn = conn |> get(path)

    res = json_response(conn, 200)

    assert res == %{
             "type" => "FeatureCollection",
             "features" => [
               %{
                 "geometry" => %{"coordinates" => [1, 1], "type" => "Point"},
                 "properties" => %{"nom_lieu" => "Ajaccio"},
                 "type" => "Feature"
               },
               %{
                 "geometry" => %{"coordinates" => [2, 2], "type" => "Point"},
                 "properties" => %{"nom_lieu" => "Coti-Chiavari"},
                 "type" => "Feature"
               }
             ]
           }
  end
end
