defmodule DB.Repo.Migrations.ContactAddSecondaryPhoneNumber do
  use Ecto.Migration

  def change do
    alter table(:contact) do
      add(:secondary_phone_number, :binary, null: true)
    end
  end
end
