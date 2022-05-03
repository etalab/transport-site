defmodule DB.Repo.Migrations.AddResourceFiletype do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add :filetype, :string
    end
  end
end
