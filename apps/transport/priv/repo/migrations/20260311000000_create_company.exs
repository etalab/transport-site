defmodule DB.Repo.Migrations.CreateCompany do
  use Ecto.Migration

  def change do
    create table(:company) do
      add(:siren, :string, primary_key: true)
      add(:nom_complet, :string)
      add(:nom_raison_sociale, :string)
      add(:sigle, :string)
      add(:date_mise_a_jour_rne, :date)
      add(:siege_adresse, :string)
      add(:siege_latitude, :float)
      add(:siege_longitude, :float)
      add(:collectivite_territoriale, :map)
      add(:est_service_public, :boolean)

      timestamps(type: :utc_datetime_usec)
    end
  end
end
