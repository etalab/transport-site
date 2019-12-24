defmodule DB.Repo.Migrations.AddResourceTags do
  use Ecto.Migration

  def change do
    alter table(:dataset) do
      add(:nb_reuses, :integer)
    end
  end
end
