defmodule DB.Repo.Migrations.DatasetCustomLogosColumns do
  use Ecto.Migration

  def change do
    alter table(:dataset) do
      add(:custom_logo, :string)
      add(:custom_full_logo, :string)
    end
  end
end
