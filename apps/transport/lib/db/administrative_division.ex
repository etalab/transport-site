defmodule DB.AdministrativeDivision do
  @moduledoc """
  AdministrativeDivision schema, in French "Collectivité Territoriale".
  This schema is used to represent the territorial divisions in France: communes, EPCI, departments and regions.
  The schema for now doesn’t show relationships between territorial divisions, such as the relationship between a commune and its EPCI or department.
  (But this relationship is available in the Commune schema, for example.)
  It relies on a single table in the database, administrative_division.
  The data is replicated (denormalized) from the dedicated commune, epci, departement and region tables.
  This is done to simplify the queries and the data model for some use cases: search, link to dataset, etc.
  Other approaches were considered, such as using a materialized view, the existing separate tables,
  but they all had drawbacks. For example, a materialized view would not allow us to use foreign keys, which is important for data integrity.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset

  typed_schema "administrative_division" do
    field(:type_insee, :string)
    field(:insee, :string)

    field(:type, Ecto.Enum,
      values: [
        :commune,
        :departement,
        :epci,
        :region
      ],
      null: false
    )

    field(:nom, :string)
    field(:geom, Geo.PostGIS.Geometry) :: Geo.MultiPolygon.t()
  end

  def changeset(administrative_division, attrs) do
    administrative_division
    |> cast(attrs, [
      :insee,
      :type,
      :type_insee,
      :nom,
      :geom
    ])
    # |> We could infer the type_insee from other fields if needed?
    |> validate_required([
      :insee,
      :type,
      :type_insee,
      :nom,
      :geom
    ])
    |> validate_inclusion(
      :type,
      ~w(commune departement epci region)a
    )

    # |> validate_type_insee_is_consistent()
  end

  # def validate_type_insee_is_consistent(changeset) do
  # changeset
  # end
end
