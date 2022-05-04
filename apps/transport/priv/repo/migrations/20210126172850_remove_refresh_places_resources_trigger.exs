defmodule DB.Repo.Migrations.RemoveRefreshPlacesResourcesTrigger do
  use Ecto.Migration

  def up do
    execute("DROP TRIGGER refresh_places_resources_trigger ON resource;")
  end

  def down do
    execute("""
    CREATE TRIGGER refresh_places_resources_trigger
    AFTER INSERT OR UPDATE OR DELETE
    ON resource
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_places();
    """)
  end
end
