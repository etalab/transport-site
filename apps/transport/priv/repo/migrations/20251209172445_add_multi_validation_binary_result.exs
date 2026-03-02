defmodule DB.Repo.Migrations.AddMultiValidationBinaryResult do
  use Ecto.Migration

  def change do
    alter table(:multi_validation) do
      add(:binary_result, :binary)
    end
  end
end
