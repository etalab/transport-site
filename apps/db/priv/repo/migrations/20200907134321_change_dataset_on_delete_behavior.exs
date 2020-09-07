defmodule DB.Repo.Migrations.ChangeDatasetOnDeleteBehavior do
  use Ecto.Migration

  def up do
    drop(constraint(:aom, "aom_parent_dataset_id_fkey"))

    alter table(:aom) do
      modify(:parent_dataset_id, references("dataset", on_delete: :nilify_all))
    end
  end

  def down do
    drop(constraint(:aom, "aom_parent_dataset_id_fkey"))

    alter table(:aom) do
      modify(:parent_dataset_id, references("dataset"))
    end
  end
end
