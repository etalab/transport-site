defmodule TransportWeb.API.AomControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory
  import OpenApiSpex.TestAssertions

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
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

    insert(:departement)

    insert(:aom,
      geom: geom,
      departement: "38",
      forme_juridique: "Communauté de communes",
      insee_commune_principale: "38185",
      siren: "247400690"
    )

    conn = conn |> get(TransportWeb.API.Router.Helpers.aom_path(conn, :by_coordinates, lon: 56.0, lat: 4.0))
    json = json_response(conn, 200)

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
