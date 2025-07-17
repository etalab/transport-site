defmodule DB.AdministrativeDivisionTest do
  use ExUnit.Case, async: true
  import DB.Factory
  doctest DB.AdministrativeDivision, import: true

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

  test "validate_type_insee_is_consistent" do
    changeset =
      DB.AdministrativeDivision.changeset(%DB.AdministrativeDivision{}, %{
        insee: "13111",
        type_insee: "commune_13111",
        type: :commune
      })

    refute Enum.any?(changeset.errors, fn {key, _} -> key == :type_insee end)

    changeset =
      DB.AdministrativeDivision.changeset(%DB.AdministrativeDivision{}, %{
        # Wrong type_insee
        type_insee: "departement_13111",
        type: :commune
      })

    assert type_insee: {"is not consistent with type and insee", []} in changeset.errors
  end

  test "search" do
    insert(:administrative_division, type: :commune, type_insee: "commune_12345", insee: "12345", nom: "Test Commune")

    insert(:administrative_division,
      type: :departement,
      type_insee: "departement_123",
      insee: "123",
      nom: "Test Departement"
    )

    territoires = DB.AdministrativeDivision.load_searchable_administrative_divisions()

    assert [
             %{
               type: :commune,
               nom: "Test Commune",
               insee: "12345",
               normalized_nom: "testcommune"
             },
             %{
               type: :departement,
               nom: "Test Departement",
               insee: "123",
               normalized_nom: "testdepartement"
             }
           ] = DB.AdministrativeDivision.search(territoires, "Test")
  end
end
