defmodule DB.Repo.Migrations.MigrateExistingOnDemandGTFSValidation do
  use Ecto.Migration

  def up do
    execute """
    update validations
    set on_the_fly_validation_metadata = on_the_fly_validation_metadata || jsonb_build_object('state', 'completed', 'type', 'gtfs')
    where not on_the_fly_validation_metadata ? 'state'
    """
  end

  def down do
    IO.puts("no going back")
  end
end
