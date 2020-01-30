defmodule DB.DatasetGeographicView do
  @moduledoc """
  View to ease the geographic metadata of a Dataset
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.{Dataset, Region}

  @primary_key false
  typed_schema "dataset_geographic_view" do
    belongs_to(:dataset, Dataset)
    belongs_to(:region, Region)
    field(:geom, Geo.PostGIS.Geometry)
  end
end
