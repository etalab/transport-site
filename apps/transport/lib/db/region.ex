defmodule DB.Region do
  @moduledoc """
  Region schema

  There's a trigger on postgres on updates, it force an update of dataset
  in order to have an up-to-date search vector
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.{AOM, Dataset, Departement}
  alias Geo.MultiPolygon
  import Ecto.Query

  typed_schema "region" do
    field(:nom, :string)
    field(:insee, :string)
    field(:geom, Geo.PostGIS.Geometry) :: MultiPolygon.t()

    has_many(:aoms, AOM)
    has_many(:departements, Departement, foreign_key: :region_insee, references: :insee)
    has_one(:datasets, Dataset)
  end

  def count_datasets_by_region_as_legal_owners do
    subquery =
      from(d in "dataset_region_legal_owner",
        # Ignore the TER dataset
        where: d.dataset_id != 239,
        group_by: d.region_id,
        select: %{region_id: d.region_id, count: count(d.dataset_id)}
      )

    query =
      from(r in DB.Region,
        # Ignore the National region
        where: r.id != 14,
        left_join: drlo in subquery(subquery),
        on: r.id == drlo.region_id,
        select: [r.id, drlo.count |> coalesce(0)]
      )

    query
  end
end
