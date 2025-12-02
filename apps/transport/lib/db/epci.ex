defmodule DB.EPCI do
  @moduledoc """
  EPCI schema.

  The EPCI are loaded by the task transport/lib/transport/import_epci.ex.
  The EPCI imported are only "à fiscalité propre". This excludes Etablissements Publics Territoriaux.
  This allows to have a 1 to 1 relation between a commune and an EPCI.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset

  typed_schema "epci" do
    field(:insee, :string)
    field(:nom, :string)
    field(:type, :string)
    field(:mode_financement, :string)
    field(:geom, Geo.PostGIS.Geometry, load_in_query: false) :: Geo.MultiPolygon.t()
    has_many(:communes, DB.Commune, foreign_key: :epci_insee)
  end

  def changeset(epci, attrs) do
    epci
    |> cast(attrs, [:insee, :nom, :geom, :type, :mode_financement])
    |> validate_required([:insee, :nom, :geom, :type, :mode_financement])
    |> validate_inclusion(:type, allowed_types())
    |> validate_inclusion(:mode_financement, allowed_mode_financement())
  end

  defp allowed_types,
    do: ["Communauté d'agglomération", "Communauté urbaine", "Communauté de communes", "Métropole", "Métropole de Lyon"]

  defp allowed_mode_financement, do: ["Fiscalité professionnelle unique", "Fiscalité additionnelle"]
end
