defmodule DB.Repo.Migrations.AddMetadatasForOnTheFlyValidations do
  use Ecto.Migration

  def change do
    alter table(:validations) do
      add(:on_the_fly_validation_metadata, :map)
    end
  end
end
