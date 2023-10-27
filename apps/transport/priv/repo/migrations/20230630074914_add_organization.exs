defmodule DB.Repo.Migrations.AddOrganization do
  use Ecto.Migration

  def change do
    create table(:organization, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:slug, :string)
      add(:name, :string)
      add(:acronym, :string)
      add(:logo, :string)
      add(:logo_thumbnail, :string)
      add(:badges, {:array, :map})
      add(:metrics, :map)
      add(:created_at, :utc_datetime_usec)
    end

    create(unique_index(:organization, [:slug]))

    create table(:contacts_organizations, primary_key: false) do
      add(:contact_id, references(:contact, on_delete: :delete_all), null: false)
      add(:organization_id, references(:organization, type: :string, on_delete: :delete_all), null: false)
    end
  end
end
