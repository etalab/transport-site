defmodule DB.Repo.Migrations.NotificationChangeDatasetOnDeleteBehavior do
  use Ecto.Migration

  def up do
    drop(constraint(:notifications, "notifications_dataset_id_fkey"))

    alter table(:notifications) do
      modify(:dataset_id, references(:dataset, on_delete: :nilify_all))
    end
  end

  def down do
    drop(constraint(:notifications, "notifications_dataset_id_fkey"))

    alter table(:notifications) do
      modify(:dataset_id, references(:dataset))
    end
  end
end
