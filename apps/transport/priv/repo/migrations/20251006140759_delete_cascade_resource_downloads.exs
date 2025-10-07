defmodule DB.Repo.Migrations.DeleteCascadeResourceDownloads do
  use Ecto.Migration

  def change do
    drop(constraint(:resource_download, "resource_download_resource_id_fkey"))

    alter table(:resource_download) do
      modify(:resource_id, references(:resource, on_delete: :delete_all))
    end
  end
end
