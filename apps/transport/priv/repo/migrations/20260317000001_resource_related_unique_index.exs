defmodule DB.Repo.Migrations.ResourceRelatedUniqueIndexSrcDstReason do
  use Ecto.Migration

  def change do
    create(unique_index(:resource_related, [:resource_src_id, :resource_dst_id, :reason]))
  end
end
