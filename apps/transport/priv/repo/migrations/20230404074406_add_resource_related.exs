defmodule DB.Repo.Migrations.AddResourceRelated do
  use Ecto.Migration

  def change do
    create table(:resource_related, primary_key: false) do
      add(:resource_src_id, references(:resource), on_delete: :delete_all, null: false)
      add(:resource_dst_id, references(:resource), on_delete: :delete_all, null: false)
      add(:reason, :string, null: false)
    end

    create(index(:resource_related, [:resource_src_id]))
    create(index(:resource_related, [:reason]))
  end
end
