defmodule DB.Repo.Migrations.AddGeojsonToValidationData do
  use Ecto.Migration

  def change do
    alter table(:validations) do
      add(:data_vis, :map)
    end
  end
end
