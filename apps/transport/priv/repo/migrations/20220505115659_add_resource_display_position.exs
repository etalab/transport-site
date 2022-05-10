defmodule DB.Repo.Migrations.AddResourceDisplayPosition do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add :display_position, :integer
    end
  end
end
