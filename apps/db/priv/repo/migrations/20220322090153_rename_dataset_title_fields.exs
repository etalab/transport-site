defmodule DB.Repo.Migrations.RenameDatasetTitleFields do
  use Ecto.Migration

  def change do
    rename table(:dataset), :title, to: :datagouv_title
  end
end
