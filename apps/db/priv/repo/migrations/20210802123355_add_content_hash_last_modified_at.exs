defmodule DB.Repo.Migrations.AddContentHashLastModifiedAt do
  use Ecto.Migration

  def change do
    alter table("resource") do
      add :content_hash_last_modified_at, :utc_datetime
    end
  end
end
