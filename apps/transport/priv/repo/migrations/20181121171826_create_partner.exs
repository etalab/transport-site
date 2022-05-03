defmodule DB.Repo.Migrations.CreatePartner do
  use Ecto.Migration

  def change do
    create table(:partner) do
      add :page, :string
      add :api_uri, :string
      add :name, :string
    end
  end
end
