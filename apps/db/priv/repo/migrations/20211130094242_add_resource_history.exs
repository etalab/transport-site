defmodule DB.Repo.Migrations.AddResourceHistory do
  use Ecto.Migration

  def change do
    create table("resource_history") do
      # FIX ME
      # We should be able to add a foreign key to resource.datagouv_id
      # but for now datagouv_id is not unique
      add :datagouv_id, :string, null: false
      add :version, :integer, null: false
      add :payload, :jsonb, null: false

      timestamps([type: :utc_datetime_usec])
    end

    create index("resource_history", [:datagouv_id])
  end
end
