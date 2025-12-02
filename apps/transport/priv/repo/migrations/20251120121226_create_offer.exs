defmodule DB.Repo.Migrations.CreateOffer do
  use Ecto.Migration

  def change do
    create table(:offer) do
      add(:nom_commercial, :string, null: false)
      add(:identifiant_offre, :integer, null: false)
      add(:type_transport, :string, null: false)
      add(:modes, {:array, :string}, null: false)
      add(:nom_aom, :string, null: false)
      add(:aom_siren, :string, null: false)
      add(:aom_id, references(:aom))
      add(:niveau, :string, null: false)
      add(:exploitant, :string, null: true)
      add(:type_contrat, :string, null: true)
      add(:territoire, :string, null: false, size: 5_000)
      timestamps(type: :utc_datetime_usec)
    end
  end
end
