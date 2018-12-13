defmodule Transport.Commune do
  @moduledoc """
  Commune schema
  """
  use Ecto.Schema
  alias Transport.AOM

  schema "commune" do
      field :insee, :string
      field :nom, :string
      field :wikipedia, :string
      field :surf_ha, :float
      field :geom, Geo.PostGIS.Geometry

      belongs_to :aom_res, AOM, references: :composition_res_id
  end
end
