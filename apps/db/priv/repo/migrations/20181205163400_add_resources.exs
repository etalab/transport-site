defmodule DB.Repo.Migrations.AddResources do
  use Ecto.Migration

  def change do
    create table(:resource) do
      add :validations, :map
      add :validation_date, :string
      add :is_active, :boolean
      add :url, :string

      add :dataset_id, references(:dataset)
    end
  end
end
