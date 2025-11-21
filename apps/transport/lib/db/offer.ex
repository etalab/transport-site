defmodule DB.Offer do
  @moduledoc """
  Represents transport offers.
  """
  use TypedEctoSchema
  use Ecto.Schema
  import Ecto.Changeset

  typed_schema "offer" do
    field(:nom_commercial, :string)
    field(:identifiant_offre, :integer)
    field(:type_transport, :string)
    field(:modes, {:array, :string})
    field(:nom_aom, :string)
    field(:aom_siren, :string)
    field(:niveau, :string)
    field(:exploitant, :string)
    field(:type_contrat, :string)
    field(:territoire, :string)

    timestamps(type: :utc_datetime_usec)

    belongs_to(:aom, DB.AOM)
  end

  def changeset(model, attrs) do
    model
    |> cast(attrs, [
      :nom_commercial,
      :identifiant_offre,
      :type_transport,
      :nom_aom,
      :aom_siren,
      :niveau,
      :exploitant,
      :type_contrat,
      :territoire
    ])
    |> transform_modes(attrs)
    |> add_aom(attrs)
    |> validate_required([
      :nom_commercial,
      :identifiant_offre,
      :type_transport,
      :modes,
      :nom_aom,
      :aom_siren,
      :niveau,
      :territoire
    ])
  end

  defp transform_modes(%Ecto.Changeset{} = changeset, %{"modes" => modes}) do
    put_change(changeset, :modes, String.split(modes, " "))
  end

  defp add_aom(%Ecto.Changeset{} = changeset, %{"aom_siren" => aom_siren, "nom_aom" => nom_aom}) do
    aom =
      try do
        DB.Repo.get_by(DB.AOM, siren: aom_siren)
      rescue
        Ecto.MultipleResultsError ->
          DB.Repo.get_by(DB.AOM, nom: nom_aom)
      end

    put_assoc(changeset, :aom, aom)
  end
end
