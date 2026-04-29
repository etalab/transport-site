defmodule DB.Company do
  @moduledoc """
  Represents a French company identified by its SIREN number.
  Data is fetched from the "Recherche d'entreprises API".
  See `Transport.Companies`.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key {:siren, :string, []}

  typed_schema "company" do
    field(:nom_complet, :string)
    field(:nom_raison_sociale, :string)
    field(:sigle, :string)
    field(:date_mise_a_jour_rne, :date)
    field(:siege_adresse, :string)
    field(:siege_latitude, :float)
    field(:siege_longitude, :float)
    field(:collectivite_territoriale, :map)
    field(:est_service_public, :boolean)

    timestamps(type: :utc_datetime_usec)
  end

  @fields [
    :siren,
    :nom_complet,
    :nom_raison_sociale,
    :sigle,
    :date_mise_a_jour_rne,
    :siege_adresse,
    :siege_latitude,
    :siege_longitude,
    :collectivite_territoriale,
    :est_service_public
  ]

  def changeset(struct, attrs \\ %{}) do
    struct
    |> cast(attrs, @fields)
    |> validate_required([:siren])
  end
end
