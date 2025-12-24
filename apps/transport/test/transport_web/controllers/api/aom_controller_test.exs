defmodule TransportWeb.API.AomControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory
  import OpenApiSpex.TestAssertions

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "GET /api/aoms/:insee", %{conn: conn} do
    insert(:departement, insee: "76")
    commune = insert(:commune, insee: "76217", aom_siren: "247600786")

    insert(:aom,
      siren: commune.aom_siren,
      departement: "76",
      forme_juridique: "Communauté de communes",
      nom: "CA de la région Dieppoise",
      insee_commune_principale: "76217"
    )

    json = conn |> get(TransportWeb.API.Router.Helpers.aom_path(conn, :by_insee, commune.insee)) |> json_response(200)

    assert_response_schema(json, "AOMResponse", TransportWeb.API.Spec.spec())

    assert json == %{
             "departement" => "76",
             "forme_juridique" => "Communauté de communes",
             "insee_commune_principale" => "76217",
             "nom" => "CA de la région Dieppoise",
             "siren" => "247600786"
           }
  end

  test "GET /api/aoms/geojson", %{conn: conn} do
    insert(:departement, insee: "38")

    insert(:aom,
      geom: %Geo.Polygon{
        coordinates: [
          [
            {55.0, 3.0},
            {60.0, 3.0},
            {60.0, 5.0},
            {55.0, 5.0},
            {55.0, 3.0}
          ]
        ],
        srid: 4326,
        properties: %{}
      },
      nom: "Grenoble",
      departement: "38",
      forme_juridique: "Communauté de communes",
      insee_commune_principale: "38185",
      siren: "247400690"
    )

    json = conn |> get(TransportWeb.API.Router.Helpers.aom_path(conn, :geojson)) |> json_response(200)

    assert_response_schema(json, "GeoJSONResponse", TransportWeb.API.Spec.spec())

    assert json == %{
             "features" => [
               %{
                 "geometry" => %{
                   "coordinates" => [[[55.0, 3.0], [60.0, 3.0], [60.0, 5.0], [55.0, 5.0], [55.0, 3.0]]],
                   "crs" => %{"properties" => %{"name" => "EPSG:4326"}, "type" => "name"},
                   "type" => "Polygon"
                 },
                 "properties" => %{
                   "departement" => "38",
                   "forme_juridique" => "Communauté de communes",
                   "insee_commune_principale" => "38185",
                   "nom" => "Grenoble",
                   "siren" => "247400690"
                 },
                 "type" => "Feature"
               }
             ],
             "type" => "FeatureCollection"
           }
  end

  test "GET /api/aoms (by_coordinates)", %{conn: conn} do
    geom = %Geo.Polygon{
      coordinates: [
        [
          {55.0, 3.0},
          {60.0, 3.0},
          {60.0, 5.0},
          {55.0, 5.0},
          {55.0, 3.0}
        ]
      ],
      srid: 4326,
      properties: %{}
    }

    insert(:departement, insee: "38")

    insert(:aom,
      geom: geom,
      nom: "Grenoble",
      departement: "38",
      forme_juridique: "Communauté de communes",
      insee_commune_principale: "38185",
      siren: "247400690"
    )

    json =
      conn
      |> get(TransportWeb.API.Router.Helpers.aom_path(conn, :by_coordinates, lon: 56.0, lat: 4.0))
      |> json_response(200)

    assert_response_schema(json, "AOMResponse", TransportWeb.API.Spec.spec())

    assert json == %{
             "departement" => "38",
             "forme_juridique" => "Communauté de communes",
             "insee_commune_principale" => "38185",
             "nom" => "Grenoble",
             "siren" => "247400690"
           }
  end
end
