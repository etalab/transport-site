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

    insert(:aom, geom: geom)

    conn = conn |> get(TransportWeb.API.Router.Helpers.aom_path(conn, :by_coordinates, lon: 56.0, lat: 4.0))
    json = json_response(conn, 200)

    # apparently, currently returning only one AOM
    assert json == %{
             "departement" => "The one",
             "forme_juridique" => nil,
             "insee_commune_principale" => "38185",
             "nom" => "Grenoble",
             "siren" => nil
           }

    # TODO: fix this - this should raise, because `AOMResponse` is out of sync with this output
    assert_schema(json, "AOM", TransportWeb.API.Spec.spec())
  end
end
