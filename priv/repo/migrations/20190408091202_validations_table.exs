defmodule Transport.Repo.Migrations.ValidationsTable do
  use Ecto.Migration

  def change do
    create table(:validations) do
      add :details, :map
      add :date, :string
      add :resource_id, references(:resource)
    end

    alter table(:resource) do
      remove :validations
      remove :validation_date
    end
  end
end
