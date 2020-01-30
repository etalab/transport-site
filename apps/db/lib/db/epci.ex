defmodule DB.EPCI do
  @moduledoc """
  EPCI schema

  Link the EPCI to some Communes.
  The EPCI are loaded once and for all by the task transport/lib/transport/import_epci.ex
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "epci" do
    field(:code, :string)
    field(:nom, :string)

    # for the moment we don't need a link relational link to the Commune table,
    # so we only store an array of insee code
    field(:communes_insee, {:array, :string}, default: [])
  end
end
