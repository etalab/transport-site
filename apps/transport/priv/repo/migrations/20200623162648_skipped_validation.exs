defmodule DB.Repo.Migrations.SkippedValidation do
  use Ecto.Migration

  def change do
    alter table(:logs_validation) do
      add(:skipped, :boolean, default: false)
      add(:skipped_reason, :string)

      modify(:error_msg, :text)
    end
  end
end
