defmodule DB.Repo.Migrations.ResourceDatagouvId do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add(:datagouv_id, :string)
    end
  end
end
