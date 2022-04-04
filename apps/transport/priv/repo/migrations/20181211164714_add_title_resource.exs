defmodule DB.Repo.Migrations.AddTitleResource do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add :title, :string
    end
  end
end
