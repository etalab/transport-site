defmodule TransportWeb.API.GeoQueryControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "a BNLC geo query", %{conn: conn} do
    insert_parcs_relais_dataset()
    %{id: dataset_id} = insert_bnlc_dataset()

    %{id: resource_history_id} = insert(:resource_history, %{payload: %{"dataset_id" => dataset_id}})
    %{id: geo_data_import_id} = insert(:geo_data_import, %{resource_history_id: resource_history_id})

    %{id: geo_data_import_id_ko} = insert(:geo_data_import)

    point1 = %Geo.Point{coordinates: {1, 1}, srid: 4326}
    point2 = %Geo.Point{coordinates: {2, 2}, srid: 4326}

    insert(:geo_data, %{geo_data_import_id: geo_data_import_id, geom: point1, payload: %{"nom_lieu" => "Ajaccio"}})

    insert(:geo_data, %{geo_data_import_id: geo_data_import_id, geom: point2, payload: %{"nom_lieu" => "Coti-Chiavari"}})

    insert(:geo_data, %{geo_data_import_id: geo_data_import_id_ko, geom: point2, payload: %{"nom_lieu" => "Bastia"}})

    conn = conn |> get(TransportWeb.API.Router.Helpers.geo_query_path(conn, :index, data: "bnlc"))

    assert json_response(conn, 200) == %{
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

  test "a parkings relais geo query", %{conn: conn} do
    insert_bnlc_dataset()
    %{id: dataset_id} = insert_parcs_relais_dataset()

    %{id: resource_history_id} = insert(:resource_history, %{payload: %{"dataset_id" => dataset_id}})
    %{id: geo_data_import_id} = insert(:geo_data_import, %{resource_history_id: resource_history_id})

    %{id: geo_data_import_id_ko} = insert(:geo_data_import)

    point1 = %Geo.Point{coordinates: {1, 1}, srid: 4326}
    point2 = %Geo.Point{coordinates: {2, 2}, srid: 4326}

    insert(:geo_data, %{
      geo_data_import_id: geo_data_import_id,
      geom: point1,
      payload: %{"nom" => "Nuits-Saint-Georges", "nb_pr" => 22}
    })

    insert(:geo_data, %{
      geo_data_import_id: geo_data_import_id,
      geom: point2,
      payload: %{"nom" => "Gevrey-Chambertin", "nb_pr" => 23}
    })

    insert(:geo_data, %{
      geo_data_import_id: geo_data_import_id_ko,
      geom: point2,
      payload: %{"nom" => "Rouen", "nb_pr" => 50}
    })

    conn = conn |> get(TransportWeb.API.Router.Helpers.geo_query_path(conn, :index, data: "parkings-relais"))

    assert json_response(conn, 200) == %{
             "type" => "FeatureCollection",
             "features" => [
               %{
                 "geometry" => %{"coordinates" => [1, 1], "type" => "Point"},
                 "properties" => %{"nom" => "Nuits-Saint-Georges", "nb_pr" => 22},
                 "type" => "Feature"
               },
               %{
                 "geometry" => %{"coordinates" => [2, 2], "type" => "Point"},
                 "properties" => %{"nom" => "Gevrey-Chambertin", "nb_pr" => 23},
                 "type" => "Feature"
               }
             ]
           }
  end

  test "404 cases", %{conn: conn} do
    insert_bnlc_dataset()
    insert_parcs_relais_dataset()

    conn
    |> get(TransportWeb.API.Router.Helpers.geo_query_path(conn, :index))
    |> json_response(404)

    conn
    |> get(TransportWeb.API.Router.Helpers.geo_query_path(conn, :index, data: Ecto.UUID.generate()))
    |> json_response(404)
  end

  defp insert_bnlc_dataset do
    insert(:dataset, %{
      type: "carpooling-areas",
      organization: Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)
    })
  end

  defp insert_parcs_relais_dataset do
    insert(:dataset, %{
      type: "private-parking",
      custom_title: "Base nationale des parcs relais",
      organization: Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)
    })
  end
end
