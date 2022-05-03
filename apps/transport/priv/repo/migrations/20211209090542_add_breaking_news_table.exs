defmodule DB.Repo.Migrations.AddBreakingNewsTable do
  use Ecto.Migration

  def change do
    create table(:breaking_news) do
      add :level, :string
      add :msg, :string
    end
  end
end
