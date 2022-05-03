defmodule DB.Repo.Migrations.ImportLogsUnlimitedTextLengthLogsTable do
  use Ecto.Migration

  def change do
    alter table(:logs_import) do
      modify(:error_msg, :text)
    end
  end
end
