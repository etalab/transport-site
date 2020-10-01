defmodule DB.Repo.Migrations.ResourceModes do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add(:modes, {:array, :string}, default: [])
    end
  end
end
