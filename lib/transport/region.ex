defmodule Transport.Region do
  @moduledoc """
  Region schema
  """
  use Ecto.Schema
  alias Transport.{AOM, Dataset}
  import  Ecto.Query

  schema "region" do
    field :nom, :string
    field :insee, :string
    field :is_completed, :boolean
    field :geom, Geo.PostGIS.Geometry

    has_many :aoms, AOM
    has_one :datasets, Dataset
  end

  def search(search_term) do
    from r in __MODULE__,
     where: fragment("? @@ plainto_tsquery('french', ?)", r.nom, ^search_term)
  end
end
