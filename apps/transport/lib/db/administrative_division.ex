defmodule DB.AdministrativeDivision do
  @moduledoc """
  AdministrativeDivision schema.

  This concept is used to represent various levels of divisions of the French territory:
  - Communes
  - Departments
  - Regions
  - [EPCIs](https://fr.wikipedia.org/wiki/Établissement_public_de_coopération_intercommunale)
  - The whole country itself
  - (more could actually be added here)

  Unlike pre-existing concepts (`DB.Commune`/`DB.Region`/`DB.EPCI`), `DB.AdministrativeDivision` does not currently
  include relationships between the various entities.

  At the moment, data is replicated & denormalised from the `commune`, `epci`, `departement` and `region` tables.
  This is done to simplify the queries and the data model for some use cases: search, link to dataset, etc.

  Other approaches were considered (such as using a materialized view, leveraging the existing separate tables).
  For example, a materialized view would not allow us to use foreign keys, which is important for data integrity.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset
  use Gettext, backend: TransportWeb.Gettext

  @types ~w(commune departement epci region pays)a

  typed_schema "administrative_division" do
    # type_insee is a unique meaningful identifier, e.g. "commune_75056" for Paris
    field(:type_insee, :string)

    field(:insee, :string)

    field(:type, Ecto.Enum,
      values: @types,
      null: false
    )

    field(:nom, :string)
    field(:geom, Geo.PostGIS.Geometry) :: Geo.MultiPolygon.t()
  end

  # NOTE: we could infer the type_insee from other fields if needed?
  @cast_attributes [
    :insee,
    :type,
    :type_insee,
    :nom,
    :geom
  ]

  def changeset(administrative_division, attrs) do
    administrative_division
    |> cast(attrs, @cast_attributes)
    |> validate_required(@cast_attributes)
    |> validate_inclusion(:type, @types)
    |> validate_type_insee_is_consistent()
  end

  def validate_type_insee_is_consistent(changeset) do
    type_insee = get_field(changeset, :type_insee)
    type = get_field(changeset, :type)
    insee = get_field(changeset, :insee)

    if type_insee && type && insee && "#{type}_#{insee}" == type_insee do
      changeset
    else
      add_error(changeset, :type_insee, "is not consistent with type and insee")
    end
  end

  @doc """
  Used for search, quick example use:

  iex> insert(:administrative_division, nom: "FouDouFaFa")
  iex> (search(load_searchable_administrative_divisions(), "fou") |> hd()).nom
  "FouDouFaFa"
  """
  def load_searchable_administrative_divisions do
    Transport.SearchCommunes.load_administrative_divisions()
  end

  def search(territoires, term) do
    Transport.SearchCommunes.filter(territoires, term)
  end

  def display_type(%DB.AdministrativeDivision{type: :commune}), do: dgettext("administrative_division", "municipality")

  def display_type(%DB.AdministrativeDivision{type: :departement}),
    do: dgettext("administrative_division", "department")

  def display_type(%DB.AdministrativeDivision{type: :epci}), do: dgettext("administrative_division", "EPCI")
  def display_type(%DB.AdministrativeDivision{type: :region}), do: dgettext("administrative_division", "region")
  def display_type(%DB.AdministrativeDivision{type: :pays}), do: dgettext("administrative_division", "country")
end
