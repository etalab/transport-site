defmodule DB.Repo.Migrations.DatasetAddIsHidden do
  use Ecto.Migration

  def change do
    alter table(:dataset) do
      add(:is_hidden, :boolean, default: false, null: false)
    end
  end
end
