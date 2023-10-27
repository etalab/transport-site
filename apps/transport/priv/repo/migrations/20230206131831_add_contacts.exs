defmodule DB.Repo.Migrations.AddContacts do
  use Ecto.Migration

  def change do
    create table(:contact) do
      add(:first_name, :string, null: false)
      add(:last_name, :string, null: false)
      add(:organization, :string, null: false)
      add(:job_title, :string, null: true)
      add(:email, :binary, null: false)
      # Will be used for searching
      # https://hexdocs.pm/cloak_ecto/install.html#create-your-schema
      add(:email_hash, :binary, null: false)
      add(:phone_number, :binary, null: true)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:contact, [:email_hash], name: :contact_email_hash_index))
  end
end
