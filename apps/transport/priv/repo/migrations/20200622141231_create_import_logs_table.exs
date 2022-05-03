defmodule DB.Repo.Migrations.CreateImportLogsTable do
  use Ecto.Migration

  def change do
    create table(:logs_import) do
      add(:dataset_id, references(:dataset))
      add(:datagouv_id, :string)
      add(:timestamp, :utc_datetime)
      add(:is_success, :boolean)
      add(:error_msg, :string)
    end
  end
end
