defmodule DB.Repo.Migrations.ResourceRelatedOnDelete do
  use Ecto.Migration

  def change do
    # Review foreign key settings previously set in
    # 20230404074406_add_resource_related.exs
    alter table(:resource_related) do
      modify(:resource_src_id, references(:resource, on_delete: :delete_all),
        from: references(:resource, on_delete: :nothing)
      )

      modify(:resource_dst_id, references(:resource, on_delete: :delete_all),
        from: references(:resource, on_delete: :nothing)
      )
    end
  end
end
