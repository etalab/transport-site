defmodule DB.Repo.Migrations.ResourceFormatOverride do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add(:format_override, :string)
    end
  end
end
