defmodule Transport.Repo.Migrations.CreateProcessingReports do
  use Ecto.Migration

  def change do
    create table(:processing_reports) do
      add :content, :map

      timestamps()
    end
  end
end
