defmodule DB.Repo.Migrations.SkipedValidation do
  use Ecto.Migration

  def change do
    alter table(:logs_validation) do
      add(:skiped, :boolean, default: false)
      add(:skiped_reason, :string)

      modify(:error_msg, :text)
    end
  end
end
