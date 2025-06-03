defmodule DB.Repo.Migrations.DefaultToken do
  use Ecto.Migration

  def change do
    alter table(:token) do
      remove(:default_for_contact_id)
    end

    create table(:default_token) do
      add(:contact_id, references(:contact, on_delete: :delete_all), null: false)
      add(:token_id, references(:token, on_delete: :delete_all), null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:default_token, [:contact_id]))
  end
end
