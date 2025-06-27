defmodule DB.AdministrativeDivisionTest do
  use ExUnit.Case, async: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "can save and get a territorial division" do
    # Don’t know in reality if it’s needed to have a changeset function
    # We’ll never write new administrative divisions
    # But it has proven useful to test the model behaved correctly
    %DB.AdministrativeDivision{}
    |> DB.AdministrativeDivision.changeset(%{
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

    assert %DB.AdministrativeDivision{type_insee: "commune_13111"} =
             DB.AdministrativeDivision |> Ecto.Query.last() |> DB.Repo.one!()
  end
end
