defmodule DB.Repo.Migrations.ValidationSha do
  use Ecto.Migration

  def change do
    alter table(:validations) do
      add :validation_latest_content_hash, :string
    end
  end
end
