defmodule DB.Repo.Migrations.EnableTriggerRefreshPlacesCommuneTrigger do
  use Ecto.Migration

  def change do
    execute "ALTER TABLE commune ENABLE TRIGGER refresh_places_commune_trigger;"
  end
end
