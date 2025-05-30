defmodule DB.Repo.Migrations.TokenAddDefaultForContactId do
  use Ecto.Migration

  def change do
    alter table(:token) do
      add(:default_for_contact_id, references(:contact, on_delete: :delete_all))
    end

    create(index(:token, [:default_for_contact_id]))
  end
end
