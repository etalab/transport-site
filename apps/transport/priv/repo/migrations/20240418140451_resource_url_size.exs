defmodule DB.Repo.Migrations.ResourceUrlSize do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      modify(:url, :string, size: 500, from: {:string, size: 255})
    end
  end
end
