defmodule DB.Repo.Migrations.Token do
  use Ecto.Migration

  def change do
    create table(:token) do
      add(:name, :string, null: false)
      add(:secret, :binary, null: false)
      # Will be used for searching
      # https://hexdocs.pm/cloak_ecto/install.html#create-your-schema
      add(:secret_hash, :binary, null: false)
      add(:contact_id, references(:contact, on_delete: :delete_all))
      add(:organization_id, references(:organization, type: :string, on_delete: :delete_all))

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:token, [:organization_id]))
    create(index(:token, [:secret_hash]))
    create(unique_index(:token, [:organization_id, :name]))
  end
end
