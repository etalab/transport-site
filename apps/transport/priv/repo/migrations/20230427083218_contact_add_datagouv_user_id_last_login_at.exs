defmodule DB.Repo.Migrations.ContactAddDatagouvUserIdAndLastLoginAt do
  use Ecto.Migration

  def change do
    alter table(:contact) do
      add :datagouv_user_id, :string, null: true
      add :last_login_at, :utc_datetime_usec, null: true
    end
    create_if_not_exists(unique_index(:contact, [:datagouv_user_id]))
  end
end
