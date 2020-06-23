defmodule DB.Repo.Migrations.CreateValidationLogsTable do
  use Ecto.Migration

  def change do
    create table(:logs_validation) do
      add(:resource_id, references(:resource))
      add(:dataset_id, :integer)
      add(:timestamp, :utc_datetime)
      add(:is_success, :boolean)
      add(:error_msg, :text)
    end
  end
end
