defmodule DB.Repo.Migrations.ContactAddLocale do
  use Ecto.Migration

  def change do
    alter table(:contact) do
      add(:locale, :string, default: "fr")
    end
  end
end
