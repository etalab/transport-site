defmodule DB.Repo.Migrations.MoveFieldsToJsonb do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      modify(:metadata, :jsonb)
    end
    alter table(:validations) do
      modify(:details, :jsonb)
      modify(:on_the_fly_validation_metadata, :jsonb)
      modify(:data_vis, :jsonb)
    end
  end
end
