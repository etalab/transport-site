defmodule DB.Repo.Migrations.AddNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add(:reason, :string, null: false)
      add(:dataset_id, references(:dataset, on_delete: :nothing))
      add(:email, :binary, null: false)
      # Will be used for searching
      # https://hexdocs.pm/cloak_ecto/install.html#create-your-schema
      add(:email_hash, :binary, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:notifications, [:dataset_id]))
    create(index(:notifications, [:email_hash]))
  end
end
