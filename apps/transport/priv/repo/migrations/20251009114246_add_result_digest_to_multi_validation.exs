defmodule DB.Repo.Migrations.AddResultDigestToMultiValidation do
  use Ecto.Migration

  def change do
    alter table(:multi_validation) do
      add(:digest, :jsonb)
    end
  end
end
