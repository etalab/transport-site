defmodule DB.TerritorialDivisionTest do
  use ExUnit.Case, async: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "can save and get a territorial division" do
    %DB.TerritorialDivision{}
    |> DB.TerritorialDivision.changeset(%{
      insee: "13111",
      type_insee: "commune_13111",
      type: :commune,
      nom: "Vauvenargues",
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
      }
    })
    |> DB.Repo.insert()

    assert %DB.TerritorialDivision{type_insee: "commune_13111"} =
             DB.TerritorialDivision |> Ecto.Query.last() |> DB.Repo.one!()
  end
end
