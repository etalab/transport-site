defmodule DB.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    # TO DO check Oban migration policy
    Oban.Migrations.up(version: 10)
  end

  # We specify `version: 1` in `down`, ensuring that we'll roll all the way back down if
  # necessary, regardless of which version we've migrated `up` to.
  def down do
    Oban.Migrations.down(version: 1)
  end
end
