defmodule DB.Repo.Migrations.AddTypeIdPartner do
  use Ecto.Migration

  def up do
    alter table(:partner) do
      add :type, :string
      add :datagouv_id, :string
      remove :api_uri
    end
  end

  def down do
    alter table(:partner) do
      remove :type
      remove :datagouv_id
      add :api_uri, :string
    end
  end
end
