defmodule DB.Repo.Migrations.NotificationsAddDatasetDatagouvId do
  use Ecto.Migration

  def change do
    alter table(:notifications) do
      add(:dataset_datagouv_id, :string)
    end
  end
end
