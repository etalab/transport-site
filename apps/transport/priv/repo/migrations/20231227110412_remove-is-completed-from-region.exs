defmodule :"Elixir.DB.Repo.Migrations.Remove-is-completed-from-region" do
  use Ecto.Migration

  def change do
    alter table(:region) do
      remove :is_completed, :boolean
    end
  end
end
