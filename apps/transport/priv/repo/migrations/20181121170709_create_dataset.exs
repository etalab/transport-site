defmodule Transport.Repo.Migrations.CreateDataset do
  use Ecto.Migration

  def change do
    create table(:dataset) do
      add :coordinates, {:array, :float}
      add :datagouv_id, :string
      add :spatial, :string
      add :created_at, :string
      add :description, :text
      add :download_url, :string
      add :format, :string
      add :frequency, :string
      add :last_update, :string
      add :last_import, :string
      add :licence, :string
      add :logo, :string
      add :full_logo, :string
      add :slug, :string
      add :tags, {:array, :string}
      add :task_id, :string
      add :title, :string
      add :type, :string
      add :metadata, :map
      add :validations, :map
      add :validation_date, :string

      add :region_id, references(:region)
      add :aom_id, references(:aom)
    end
  end
end
