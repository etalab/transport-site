defmodule DB.Repo.Migrations.AddDatasetSearchPayload do
  use Ecto.Migration

  def change do
    alter table(:dataset) do
      add(:search_payload, :map, default: %{})
    end
  end
end
