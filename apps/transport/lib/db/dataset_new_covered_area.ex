defmodule DB.DatasetNewCoveredArea do
  @moduledoc """
  This module defines one area covered by a dataset (that can have many).
  It’s goal is to replace the old dataset covered area mechanism.
  """

  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset

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

    def changeset(dataset_new_covered_area, attrs) do
      dataset_new_covered_area
      |> cast(attrs, [
        :dataset_id,
        :administrative_division_type,
        :commune_id,
        :departement_id,
        :epci_id,
        :region_id
      ])
      |> validate_required([
        :administrative_division_type
      ])
      |> validate_inclusion(
        :administrative_division_type,
        ~w(commune departement epci region)a
      )
      |> validate_one_administrative_division()
    end

    @doc """
    Used for search, usage:
    territoires = DB.DatasetNewCoveredArea.load_searchable_administrative_divisions
    DB.DatasetNewCoveredArea.search(territoires, "75")
    """
    def load_searchable_administrative_divisions do
      [DB.Commune, DB.EPCI, DB.Departement, DB.Region]
      |> Enum.map(&Transport.SearchCommunes.load/1)
      |> List.flatten()
      # Take out the national region as it doesn’t have an insee code and search fails
      #  Fix this in the future
      |> Enum.reject(&(&1.nom == "National"))
      |> Enum.map(&put_administrative_division_type/1)
    end

    def search(territoires, term) do
      Transport.SearchCommunes.filter(territoires, term)
    end

    def get_administrative_division(insee, type) do
      division =
        case type do
          "commune" -> DB.Commune
          "epci" -> DB.EPCI
          "departement" -> DB.Departement
          "region" -> DB.Region
        end
        |> DB.Repo.get_by(insee: insee)

      division |> put_administrative_division_type()
    end

    defp put_administrative_division_type(division) do
      type_name = division.__struct__ |> Module.split() |> List.last() |> String.downcase()

      division
      |> Map.take([:id, :insee, :nom, :normalized_nom])
      # Todo: change that to match the struct with administrative_division_type?
      |> Map.put(:type, type_name)
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

  defp validate_one_administrative_division(changeset) do
    # TODO: Check that only one of the administrative division fields is set
    # and it matches administrative_division_type
    possible_divisions = [:commune, :departement, :epci, :region]
    administrative_division_type = get_field(changeset, :administrative_division_type)
    should_be_empty = possible_divisions -- [administrative_division_type]

    changeset =
      Enum.reduce(should_be_empty, changeset, fn division, changeset ->
        if get_field(changeset, String.to_atom("#{division}_id")) do
          add_error(changeset, "#{division}_id", "must be empty")
        else
          changeset
        end
      end)

    if get_field(changeset, String.to_atom("#{administrative_division_type}_id")) do
      changeset
    else
      add_error(changeset, "#{administrative_division_type}_id", "must be set")
    end
  end
end
