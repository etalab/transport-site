defmodule DB.Repo.Migrations.ProxyRequestAddCount do
  use Ecto.Migration

  def change do
    alter table(:proxy_request) do
      add(:count, :integer, default: 1, null: false)
    end

    create_if_not_exists(unique_index(:proxy_request, [:time, :token_id, :proxy_id]))
  end
end
