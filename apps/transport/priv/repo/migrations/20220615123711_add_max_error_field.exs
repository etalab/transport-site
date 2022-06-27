defmodule DB.Repo.Migrations.AddMaxErrorField do
  use Ecto.Migration

  def change do
    alter table(:multi_validation) do
      add :max_error, :text
    end

  end
end
