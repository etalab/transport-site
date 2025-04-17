defmodule DB.DatasetNewCoveredArea do
  @moduledoc """
  This module defines one area covered by a dataset (that can have many).
  It’s goal is to replace the old dataset covered area mechanism.
  """

  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "dataset_new_covered_area" do
    belongs_to(:dataset, DB.Dataset)
    belongs_to(:commune, DB.Commune)
    belongs_to(:epci, DB.EPCI)
    belongs_to(:departement, DB.Departement)
    belongs_to(:region, DB.Region)

    field(:administrative_division_type, Ecto.Enum,
      values: [
        :commune,
        :departement,
        :epci,
        :region
      ],
      null: false
    )

    field(:nom, :string, virtual: true)
    field(:insee, :string, virtual: true)
    field(:geom, Geo.PostGIS.Geometry, virtual: true)

    def preload_covered_area_objects(dataset) do
      dataset
      |> DB.Repo.preload(new_covered_areas: [:commune, :departement, :epci, :region])
      |> load_virtual_fields()
    end

    defp load_virtual_fields(%DB.Dataset{new_covered_areas: new_covered_areas} = dataset) do
      # Load virtual fields (nom, insee, geom) from embedded associations for an easier access
      newcovered_areas =
        new_covered_areas
        |> Enum.map(fn area ->
          level = area.administrative_division_type

          area
          |> Map.put(:nom, get_in(area, [Access.key!(level), Access.key!(:nom)]))
          |> Map.put(:insee, get_in(area, [Access.key!(level), Access.key!(:insee)]))
          |> Map.put(:geom, get_in(area, [Access.key!(level), Access.key!(:geom)]))
        end)

      %{dataset | new_covered_areas: newcovered_areas}
    end
  end
end
