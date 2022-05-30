defmodule DB.Repo.Migrations.AddMultiValidationArgs do
  use Ecto.Migration

  def change do
    alter table(:multi_validation) do
      add :oban_args, :jsonb
    end
  end
end
